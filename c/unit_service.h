#ifndef _UNIT_SERVICE_H
#define _UNIT_SERVICE_H

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <mosquitto.h>

struct unit_service_desc {
	int		fd;										// file descriptor
	int		(*read_func)(lua_State *L, int fd);		// read function
	int		(*write_func)(lua_State *L, int fd);	// read function
};

int add_service(lua_State *L);
int remove_service(lua_State *L);
int service_init(struct mosquitto *m_mosq);
int service_loop(lua_State *L);

#endif
