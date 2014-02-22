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
#include "unit.h"

/*
 * We keep a reference to the mosquitto struct so we don't have
 * to keep doing lookups ... 
 */
static struct mosquitto 	*mosq = 0;

static struct unit_service_desc	u_svc;

/*==============================================================================
 * Handle incoming messages
 *
 * Lookup the function from the _topic_callbacks table and call it with the
 * unserialized data
 *==============================================================================
 */
static void message_callback(struct mosquitto *m, void *obj, const struct mosquitto_message *msg) {
	lua_State 	*L = (lua_State *)obj;
	bool		matches = false;

	fprintf(stderr, "callback\n");

	lua_getglobal(L, "_topic_callbacks");
	if(!lua_istable(L, -1))
		luaL_error(L, "missing callbacks table, did you call init()?");

	fprintf(stderr, "1\n");
	lua_pushstring(L, msg->topic);	
	lua_rawget(L, -2);
	// If we don't have a match, we'll need to check wildcards...
	if(lua_isnil(L, -1)) {
		// nil is effectively pushed now, so we can iterate from the start
		while(lua_next(L, -2)) {
			// the topic is now at -2, function at -1
			mosquitto_topic_matches_sub((char *)lua_tostring(L, -2), msg->topic, &matches);
			if(matches) break;
			lua_pop(L, 1);
		}
		if(matches) {
			// the stack is function, key, table at this point
			// we need to get the key out of the way
			lua_remove(L, -2);
		} else {
			lua_pushnil(L);
		}
	}
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

	// TODO: data is not zero terminated, so remove these lines
	fprintf(stderr, "TOPIC: %s\n", topic);
	fprintf(stderr, "DATA: %s\n", data);
	fprintf(stderr, "LEN: %d\n", len);

	rc = mosquitto_publish(mosq, NULL, (char *)topic, len, (char *)data, 0, persist);	
	free(data);
	if(rc != MOSQ_ERR_SUCCESS) 
		return luaL_error(L, "unable to publish (err=%d)", rc);

	lua_pushnumber(L, 0);
	return 1;
}
/*==============================================================================
 * These are the read, write, and need_write functions for the service
 *==============================================================================
 */
static int mosquitto_need_write(lua_State *L, int fd) {
	mosquitto_loop_misc(mosq);				// regular housekeeping
	return mosquitto_want_write(mosq);
}
static int mosquitto_read(lua_State *L, int fd) {
	return mosquitto_loop_read(mosq, 1);
}
static int mosquitto_write(lua_State *L, int fd) {
	return mosquitto_loop_write(mosq, 1);
}

/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_reg lib[] = {
	{"subscribe", subscribe},
	{"publish", publish},
	{NULL, NULL}
};

/*------------------------------------------------------------------------------
 * Main Library Entry Point ... we initialise all of our lua functions, then
 * we work out what our module name is and setup mosquitto and the service
 * handler
 *------------------------------------------------------------------------------
 */
int luaopen_mosquitto(lua_State *L) {
	const char	*unitname;
	char		*p;
	int			rc;

	// Initialise the library...
	luaL_openlib(L, "mosquitto", lib, 0);

	// Work out what our unit name is from arg[0] (basename)
	lua_getglobal(L, "arg");
	lua_rawgeti(L, -1, 0);
	if(!lua_isstring(L, -1)) return luaL_error(L, "global variable arg[0] needs to be set with name");
	unitname = lua_tostring(L, -1);
	p = strrchr(unitname, '/'); 		// look for last slash
	if(p) unitname = p+1;
	lua_pop(L, 1);						// remove the arg table

	fprintf(stderr, "UNIT is %s\n", unitname);	

	// Initialise and create new mosquitto session...
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

	// Create the _topic_callbacks table...
	lua_newtable(L);
	lua_setglobal(L, "_topic_callbacks");

	// Initialise the service handler, and let it know about mosquitto...
	u_svc.fd = mosquitto_socket(mosq);
	u_svc.read_func = mosquitto_read;
	u_svc.write_func = mosquitto_write;
	u_svc.need_write_func = mosquitto_need_write;
	
	register_service(L, &u_svc);

	return 1;
}

