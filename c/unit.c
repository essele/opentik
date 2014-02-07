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

/*
 * We keep a reference to the mosquitto struct so we don't have
 * to keep doing lookups ... this will limit us to one instance
 */
struct mosquitto 	*mosq = 0;
int					fw_fd = 0;		// inotify_fd
int					ms_fd = 0;		// mosquitto_fd

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
	fprintf(stderr, "unit/init: got arg: %s\n", unitname);
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
	lua_newtable(L),
	lua_setglobal(L, "_topic_callbacks");

	// Initialise filewatch...
	fw_fd = filewatch_init(L);

	// Get the mosquitto fd...
	ms_fd = mosquitto_socket(mosq);

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

/*
 * LOOP
 *
 */
static int loop(lua_State *L) {
//	int rc = mosquitto_loop(mosq, -1, 1);
	fd_set				fds_rd, fds_wr;
	struct timeval		tv;
	int					rc;
	int					maxfd = 0;

	tv.tv_sec = 0;
	tv.tv_usec = 1000*1000;

	FD_ZERO(&fds_rd);
	FD_ZERO(&fds_wr);

	FD_SET(fw_fd, &fds_rd);
	FD_SET(ms_fd, &fds_rd);
	if(mosquitto_want_write(mosq)) FD_SET(ms_fd, &fds_wr);

	if(fw_fd > maxfd) maxfd=fw_fd;
	if(ms_fd > maxfd) maxfd=ms_fd;
	maxfd++;
	
	rc = select(maxfd, &fds_rd, &fds_wr, NULL, &tv);
	fprintf(stderr, "select rc=%d\n", rc);

	if(rc == 0) {
		// Timeout...
		rc = mosquitto_loop_misc(mosq);
		fprintf(stderr, "mlmisc: %d\n", rc);
	} else {
		if(FD_ISSET(ms_fd,&fds_rd)) {
			rc = mosquitto_loop_read(mosq, 1);	
			fprintf(stderr, "mlread: %d\n", rc);
		}
		if(FD_ISSET(ms_fd,&fds_wr)) {
			rc = mosquitto_loop_write(mosq, 1);	
			fprintf(stderr, "mlwrite: %d\n", rc);
		}
		if(FD_ISSET(fw_fd,&fds_rd)) {
			rc = filewatch_read(L, fw_fd);
			fprintf(stderr, "fwread: %d\n", rc);
		}
	}
	

	lua_pushnumber(L, rc);
	return 1;
} 


/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_reg lib[] = {
	{"init", init},
	{"subscribe", subscribe},
	{"publish", publish},
	{"monitor_log", monitor_log},
	{"monitor_file", monitor_file},
	{"unmonitor", unmonitor},
	{"loop", loop},
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

