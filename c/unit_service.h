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

/*
 * These are called internally by unit.c (TODO: move them there)
 */
int service_init(lua_State *L, struct mosquitto *m_mosq);
int service_loop(lua_State *L);

/*
 * Each module can register fd's to read/write with the main service loop
 * using this function.
 */
static inline void register_service(lua_State *L, struct unit_service_desc *sd) {
    void    (*reg_func)(struct unit_service_desc *sd);

    lua_getglobal(L, "__unit_register");
    reg_func = lua_touserdata(L, -1);
	reg_func(sd);
}

#endif
