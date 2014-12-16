#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/select.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "luafuncs.h"
#include "unit.h"
#include "serialize.h"

/*==============================================================================
 *
 * The UNIT is the core "module" concept, we provide a mechanism for registering
 * other services and using an event loop to call out to those other things.
 * 
 * Other modules self-register at load time.
 *
 *==============================================================================
 */


/*
 * The Globals (local to this module)
 */
static struct unit_service_desc		**services = NULL;			// Our list of services
static int 							service_slots = 0;			// How many allocated slots
static fd_set						m_read;						// Master read fds
static int							max_fd = 0;					// How many fd's for select

/*
 * Given a service descriptor as an arg, add it to our
 * service list and prepare the fdsets for select
 */
static int unit_register(struct unit_service_desc *us) {
	struct unit_service_desc	**p = NULL;
	int							i;

	// See if we have a free slot...
	for(i=0; i < service_slots; i++) {
		fprintf(stderr, "   >> slot %d = %p\n", i, services[i]);
		if(services[i] == NULL) { p = services+i; break; }
	}
	// Allocate space for the extra service if we need it...
	if(!p) {
		services = realloc(services, sizeof(struct unit_service_desc *) * (service_slots+1));
		p = services + service_slots;
		service_slots++;
	}
	*p = us;

	// Update our master read fdset and max_fd
	if(us->read_func) FD_SET(us->fd, &m_read);
	if(us->fd > max_fd) max_fd = us->fd;
	
	fprintf(stderr, "service add p=%p\n", p);
	return 0;
}

/*
 * Service Loop - we handle the mosquitto stuff here anyway, anything else
 * is a specifically added service.
 */
int service_loop(lua_State *L) {
	fd_set				fds_rd, fds_wr;
	struct timeval		tv;
	int					i;
	int					rc;

	tv.tv_sec = 0;
	tv.tv_usec = 1000*1000;

	fprintf(stderr, "service_loop()\n");

	// Our read set is simply the master set...
	fds_rd = m_read;

	// Write is harder, we need to check
	FD_ZERO(&fds_wr);
	for(i=0; i < service_slots; i++) {
		struct unit_service_desc *s = services[i];
		if(s->need_write_func && s->need_write_func(L, s->fd)) FD_SET(s->fd, &fds_wr);
	}

	rc = select(max_fd+1, &fds_rd, &fds_wr, NULL, &tv);
	fprintf(stderr, "select rc=%d\n", rc);

	if(rc > 0) {
		// Now we can look at extra services
		for(i=0; i < service_slots; i++) {
			struct unit_service_desc *s = services[i];
			if(FD_ISSET(s->fd, &fds_rd) && s->read_func) {
				rc = s->read_func(L, s->fd);
				fprintf(stderr, "service(fh=%d): read rc=%d\n", s->fd, rc);
			}
			if(FD_ISSET(s->fd, &fds_wr) && s->write_func) {
				rc = s->write_func(L, s->fd);
				fprintf(stderr, "service(fh=%d): write rc=%d\n", s->fd, rc);
			}
		}
	}
	lua_pushnumber(L, rc);
	return 1;
} 
/*==============================================================================
 * These are wrapper functions around our serialization functions to allow
 * direct Lua access
 *==============================================================================
 */
static int do_serialize(lua_State *L) {
	int		len;
	char	*rc = serialize(L, 1, &len);
	
	lua_pushlstring(L, rc, len);
	free(rc);
	return 1;
}
static int do_unserialize(lua_State *L) {
	char	*data = (char *)luaL_checkstring(L, 1);
	
	unserialize(L, data);
	return 1;
}

/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_reg lib[] = {
	{"service_loop", service_loop},
	{"serialize", do_serialize},
	{"unserialize", do_unserialize},
	{NULL, NULL}
};

/*------------------------------------------------------------------------------
 * Main Library Entry Point ... we initialise all of our lua functions, then
 * we work out what our module name is and setup mosquitto and the service
 * handler
 *------------------------------------------------------------------------------
 */
int luaopen_unit(lua_State *L) {
	// Initialise the library...
	luaL_openlib(L, "unit", lib, 0);

	// Setup the fdset
	FD_ZERO(&m_read);
	max_fd = 0;

	// Allow other modules to register services
    lua_pushlightuserdata(L, (void *)&unit_register);
    lua_setglobal(L, "__unit_register");

	return 1;
}

