#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include "mosquitto.h"
#include "unit_service.h"

/*==============================================================================
 *
 * Here we provide the capability to add and remove "services", which are
 * really just filehandles than we "select" on and then call supplied read
 * or write functions.
 *
 * We handle the mosquitto calls by default.
 *
 *==============================================================================
 */


/*
 * The Globals (local to this module)
 */
static struct unit_service_desc		**services = NULL;			// Our list of services
static int 							service_slots = 0;			// How many allocated slots
static fd_set						m_read;						// Master read fds
static fd_set						m_write;					// Master write fds
static struct mosquitto    			*mosq = 0;					// Our copy of the mosquitto handle
static int							mosq_fd = 0;				// Our copy of the mosquitto fd
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
	fprintf(stderr, "service add p=%p\n", p);
	*p = us;

	// Update our master fdsets...
	if(us->read_func) FD_SET(us->fd, &m_read);
	if(us->write_func) FD_SET(us->fd, &m_write);
	if(us->fd > max_fd) max_fd = us->fd;
	
	fprintf(stderr, "added\n");

	return 0;
}
/*
 * Given a service descriptor (lightuserdata) as an arg, add it to our
 * service list and prepare the fdsets for select
 */
int add_service(lua_State *L) {
	struct unit_service_desc	*us;
	struct unit_service_desc	**p = NULL;

	// Check if we have the right arg...
	if(!lua_islightuserdata(L, 1)) return luaL_error(L, "expecting service descriptor as argument #1\n");
	us = (struct unit_service_desc *)lua_topointer(L, 1);

	// Allocate space for the new service pointer...
	services = realloc(services, sizeof(struct unit_service_desc *) * (service_slots+1));
	p = services + service_slots;
	service_slots++;

	// Store the service pointer...
	fprintf(stderr, "service add p=%p\n", p);
	*p = us;

	// Update our master fdsets...
	if(us->read_func) FD_SET(us->fd, &m_read);
	if(us->write_func) FD_SET(us->fd, &m_write);
	if(us->fd > max_fd) max_fd = us->fd;
	
	fprintf(stderr, "added\n");

	return 0;
}

/*
 * Initialise the globals and setup the global for other modules to register
 */
int service_init(lua_State *L, struct mosquitto *m_mosq) {
	// Setup the mosquitto bits
	mosq = m_mosq;
	mosq_fd = mosquitto_socket(mosq);

	// Setup our fds's
	FD_ZERO(&m_read);
	FD_ZERO(&m_write);
	FD_SET(mosq_fd, &m_read);
	max_fd = mosq_fd;

	// Allow other modules to register services
    lua_pushlightuserdata(L, (void *)&unit_register);
    lua_setglobal(L, "__unit_register");
	return 0;
}

/*
 * Service Loop - we handle the mosquitto stuff here anyway, anything else
 * is a specifically added service.
 */
int service_loop(lua_State *L) {
//	int rc = mosquitto_loop(mosq, -1, 1);
	fd_set				fds_rd, fds_wr;
	struct timeval		tv;
	int					i;
	int					rc;

	tv.tv_sec = 0;
	tv.tv_usec = 1000*1000;

	fprintf(stderr, "service_loop()\n");

	fds_rd = m_read;
	fds_wr = m_write;
	if(mosquitto_want_write(mosq)) FD_SET(mosq_fd, &fds_wr);

	rc = select(max_fd+1, &fds_rd, &fds_wr, NULL, &tv);
	fprintf(stderr, "select rc=%d\n", rc);

	if(rc == 0) {
		// Timeout... run mosquitto housekeeping
		rc = mosquitto_loop_misc(mosq);
		fprintf(stderr, "mlmisc: %d\n", rc);
	} else {
		// First handle mosquitto operations
		if(FD_ISSET(mosq_fd,&fds_rd)) {
			rc = mosquitto_loop_read(mosq, 1);	
			fprintf(stderr, "mlread: %d\n", rc);
		}
		if(FD_ISSET(mosq_fd,&fds_wr)) {
			rc = mosquitto_loop_write(mosq, 1);	
			fprintf(stderr, "mlwrite: %d\n", rc);
		}

		// Now we can look at extra services
		for(i=0; i < service_slots; i++) {
			struct unit_service_desc *s = services[i];
			if(s && FD_ISSET(s->fd, &fds_rd) && s->read_func) {
				rc = s->read_func(L, s->fd);
				fprintf(stderr, "service(fh=%d): read rc=%d\n", s->fd, rc);
			}
			if(s && FD_ISSET(s->fd, &fds_wr) && s->write_func) {
				rc = s->write_func(L, s->fd);
				fprintf(stderr, "service(fh=%d): write rc=%d\n", s->fd, rc);
			}
		}
	}
	lua_pushnumber(L, rc);
	return 1;
} 

