#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "serialize.h"
#include "mosquitto.h"
#include "filewatch.h"
#include "luafuncs.h"
#include "netlink.h"
#include "unit_service.h"

/*
 * We keep a reference to the mosquitto struct so we don't have
 * to keep doing lookups ... this will limit us to one instance
 */
struct mosquitto 	*mosq = 0;
int					fw_fd = 0;		// inotify_fd
int					nl_fd = 0;		// netlink_fd

/*==============================================================================
 * Handle incoming messages
 *
 * Lookup the function from the _topic_callbacks table and call it with the
 * unserialized data
 *==============================================================================
 */
void message_callback(struct mosquitto *m, void *obj, const struct mosquitto_message *msg) {
	lua_State 	*L = (lua_State *)obj;

	fprintf(stderr, "callback\n");

	lua_getglobal(L, "_topic_callbacks");
	if(!lua_istable(L, -1))
		luaL_error(L, "missing callbacks table, did you call init()?");

	fprintf(stderr, "1\n");
	lua_pushstring(L, msg->topic);	
	lua_rawget(L, -2);
	if(!lua_isfunction(L, -1)) {
		fprintf(stderr, "WARN: no callback for topic [%s]\n", msg->topic);
		lua_pop(L, 2);
		return;
	}
	fprintf(stderr, "2\n");
	lua_pushstring(L, msg->topic);
	if(!unserialize(L, msg->payload)) {
		fprintf(stderr, "WARN: unable to unserialize\n");
		lua_pop(L, 3);
		return;
	}
	fprintf(stderr, "3\n");
	lua_call(L, 2, 0);
	// Pop the table...
	lua_pop(L, 1);
}

/*==============================================================================
 * This is the main unit init function, is does the following:
 * 
 * 1. Initialise the mosquitto library
 * 2. Connect to localhost
 * 3. Create a table for mapping subscriptions to functions
 * 4. Register a message handler
 *
 *==============================================================================
 */
static int init(lua_State *L) {
	char    *unitname = (char *)luaL_checkstring(L, 1);
	int		rc;

	if(mosq) return luaL_error(L, "init already called, only allowed once.");

	// Initialise and create new session...
	mosquitto_lib_init();
	mosq = mosquitto_new(unitname, true, (void *)L);
	if(!mosq) return luaL_error(L, "unable to create new mosquitto session.");

	// Connect to localhost...
	rc = mosquitto_connect(mosq, "localhost", 1883, 10);
	if(rc != MOSQ_ERR_SUCCESS) {
		if(rc == MOSQ_ERR_INVAL) {
			return luaL_error(L, "unable to connect to message broker: invalid args");
		} else {
			return luaL_error(L, "unable to connect to message broker (err=%d): %s", 
									rc, strerror(errno));	
		}
	}
	mosquitto_message_callback_set(mosq, message_callback);

	// Create the _topic_callbacks table
	lua_newtable(L);
	lua_setglobal(L, "_topic_callbacks");

	// Let the service code know about mosquitto...
	service_init(mosq);

	// Return 0
	lua_pushnumber(L, 0);
	return 1;
}

/*==============================================================================
 * Subscribe to a topic...
 *==============================================================================
 */
static int subscribe(lua_State *L) {
	char    *topic = (char *)luaL_checkstring(L, 1);
	int		rc;

	luaL_checktype(L, 2, LUA_TFUNCTION);

	// Populate the callbacks table...
	lua_getglobal(L, "_topic_callbacks");
	if(!lua_istable(L, -1))
		return luaL_error(L, "missing callbacks table, did you call init()?");

	// Push the key, then value ... and then set!
	lua_pushvalue(L, 1);
	lua_pushvalue(L, 2);
	lua_settable(L, -3);
	// Pop the table...
	lua_pop(L, 1);

	// Actually subscribe now...
	rc = mosquitto_subscribe(mosq, NULL, topic, 0);
	if(rc != MOSQ_ERR_SUCCESS) 
		return luaL_error(L, "unable to subscribe (err=%d)", rc);

	lua_pushnumber(L, 0);
	return 1;
}

/*==============================================================================
 * Publish a variable as a topic
 *
 * publish(topic, variable, bool-persist)
 *==============================================================================
 */
static int publish(lua_State *L) {
	int		len, rc;
	char    *topic = (char *)luaL_checkstring(L, 1);
	char	*data;
	bool	persist = false;

	luaL_checkany(L, 2);		// need the variable we are serializing
	data = serialize(L, 2, &len);
	if(lua_toboolean(L, 3) == 1) persist = true;

	fprintf(stderr, "TOPIC: %s\n", topic);
	fprintf(stderr, "DATA: %s\n", data);
	fprintf(stderr, "LEN: %d\n", len);

	rc = mosquitto_publish(mosq, NULL, (char *)topic, len, (char *)data, 0, persist);	
	if(rc != MOSQ_ERR_SUCCESS) 
		return luaL_error(L, "unable to publish (err=%d)", rc);

	lua_pushnumber(L, 0);
	return 1;
}

/*==============================================================================
 * Add a file to be monitored for changes
 *==============================================================================
 */
/*
static int add_monitor(lua_State *L, int type) {
	char    *filename = (char *)luaL_checkstring(L, 1);
	int		fid;
	int		rc;

	if(!lua_isfunction(L, 2)) return luaL_error(L, "expected function as second argument");
	lua_pushvalue(L, 2);
	fid = store_function(L);

	fprintf(stderr, "function reference is %d\n", fid);
	
	rc = filewatch_add(L, fid, fw_fd, filename, 0, FW_LOG);
	fprintf(stderr, "filewatch add rc=%d\n", rc);

	lua_pushnumber(L, 0);
	return 1;
}
static int monitor_log(lua_State *L) {
	return add_monitor(L, FW_LOG);
}
static int monitor_file(lua_State *L) {
	return add_monitor(L, FW_CHANGE);
}

static int unmonitor(lua_State *L) {
	char    *filename = (char *)luaL_checkstring(L, 1);
	int		rc;

	rc = filewatch_remove(fw_fd, filename);
	fprintf(stderr, "filewatch remove rc=%d\n", rc);
	if(rc > 0) free_function(L, rc);

	lua_pushnumber(L, 0);
	return 1;
}
*/

/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_reg lib[] = {
	{"init", init},
	{"subscribe", subscribe},
	{"publish", publish},
//	{"monitor_log", monitor_log},
//	{"monitor_file", monitor_file},
//	{"unmonitor", unmonitor},

// Service (filehandle monitoring) helpers
	{"add_service", add_service},
	{"remove_service", remove_service},
	{"service_loop", service_loop},
	{NULL, NULL}
};

/*------------------------------------------------------------------------------
 * Main Library Entry Point ... just intialise all the functions
 *------------------------------------------------------------------------------
 */
int luaopen_unit(lua_State *L) {
	luaL_openlib(L, "unit", lib, 0);
	return 1;
}

