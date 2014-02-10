#include <stdio.h>
#include <string.h>
#include <stdlib.h> 
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <netlink/netlink.h>
#include <netlink/cache.h>
#include <netlink/route/link.h>
#include "luafuncs.h"

/*
 * This module provides basic netlink functionality so that we can 
 * monitor (and ultimately control) link, address and route information
 */


/*
 * We have a cache manager, and then a cache for each type of record,
 * we also store the fid for each type here so we can callback events
 * to Lua
 */
static struct nl_cache_mngr	*mngr;
static struct nl_cache		*cache_link;
static int					fid_link;

/*
 * For some reason these aren't defined???
 */
#define NL_ACT_UNSPEC	0
#define NL_ACT_NEW		1
#define NL_ACT_DEL		2
#define NL_ACT_GET		3
#define NL_ACT_SET		4
#define NL_ACT_CHANGE	5

/**
 * Convert a set of flags into a hash of keys where the value is 1
 * @arg L		Lua state
 * @arg flags	flags from link
 */
void create_flags_hash(lua_State *L, unsigned int flags) {
	int 				i;
	unsigned int		mask = 1;
	char				buf[256];

	lua_newtable(L);
	for(i=0; i < 24; i++) {
		if(flags & mask) {
			lua_pushstring(L, rtnl_link_flags2str(mask, buf, sizeof(buf)));
			lua_pushnumber(L, 1);
			lua_rawset(L, -3);
		}
		mask <<= 1;
	}
}

/**
 * Call the callback function for links with link change details
 * @arg L			Lua state
 * @arg 
 */
void callback_lua_link(lua_State *L, int index, char *name, char *action) {
    get_function(L, fid_link);
    if(!lua_isfunction(L, -1)) {
        fprintf(stderr, "callback_lua_link: invalid function for callback\n");
        return;
    }
	lua_pushnumber(L, index);
    lua_pushstring(L, name);
    lua_pushstring(L, action);
    lua_call(L, 3, 0);
}

/**
 * Helper macros for setting table values for the link
 */
#define	LINK_NUM(f,code) lua_pushstring(L,f); lua_pushnumber(L, code); lua_settable(L, -3)
#define	LINK_STR(f,code) lua_pushstring(L,f); lua_pushstring(L, code); lua_settable(L, -3)

/**
 * Add/modify link details within the "nl_links" table
 * @arg L			Lua state
 * @arg link			Netlink rtnl_link object
 */
static void add_link_to_lua(lua_State *L, struct rtnl_link *link) {
	unsigned int	flags;
	int				index;
	char			buf[256];

	index = rtnl_link_get_ifindex(link);

	// Get the links table...
	lua_getglobal(L, "nl_links");

	// See if we have the index already...
	lua_rawgeti(L, -1, index);
	if(lua_isnil(L, -1)) { lua_pop(L, 1); lua_newtable(L); }
	
	LINK_NUM("index", index);
	LINK_STR("name", rtnl_link_get_name(link));
	LINK_STR("type", nl_llproto2str(rtnl_link_get_arptype(link), buf, sizeof(buf)));
	LINK_STR("operstate", rtnl_link_operstate2str(rtnl_link_get_operstate(link), buf, sizeof(buf)));
	LINK_STR("mode", rtnl_link_mode2str(rtnl_link_get_linkmode(link), buf, sizeof(buf)));
	// TODO rtnl_link_get_addr (link addr)
	LINK_NUM("mtu", rtnl_link_get_mtu(link));
	

	// flags (hash)
	lua_pushstring(L, "flags");
	flags = rtnl_link_get_flags(link);
	create_flags_hash(L, flags);
	lua_settable(L, -3);

	// Now set the table at the index...
	lua_rawseti(L, -2, index);
	lua_pop(L, 1);

}

/**
 * Remove a given link from the Lua "nl_links" table
 * @arg L		Lua state
 * @arg link	netlink link object
 */
static void remove_link_from_lua(lua_State *L, struct rtnl_link *link) {
	int				index;

	index = rtnl_link_get_ifindex(link);

	// Get the links table...
	lua_getglobal(L, "nl_links");

	// Zero the item...
	lua_pushnil(L);
	lua_rawseti(L, -2, index);
	lua_pop(L, 1);
	fprintf(stderr, "removed item index %d\n", index);
}

void	cb_link_dynamic(struct nl_cache *cache, struct nl_object *obj, int action, void *arg) {
	lua_State			*L = (lua_State *)arg;
	struct rtnl_link	*link = (struct rtnl_link *)obj;
	int					index = rtnl_link_get_ifindex(link);

	fprintf(stderr, "dynamic callback called\n");
	fprintf(stderr, "obj: %p  action: %d   arg: %p\n", obj, action, arg);

	switch(action) {
		case NL_ACT_NEW:
		case NL_ACT_CHANGE:
			add_link_to_lua(L, link);
			callback_lua_link(L, index, rtnl_link_get_name(link), (action==NL_ACT_NEW ? "add" : "change"));
			break;
		case NL_ACT_DEL:
			remove_link_from_lua(L, link);
			callback_lua_link(L, index, rtnl_link_get_name(link), "delete");
			break;
	}

	fprintf(stderr, "  XXindex: %d\n", index);
	fprintf(stderr, "  XXname: %s\n", rtnl_link_get_name(link));
	fprintf(stderr, "  XXtype: %d\n", rtnl_link_get_arptype(link));
}


void	cb_link_initial(struct nl_object *obj, void *arg) {
	lua_State			*L = (lua_State *)arg;
	struct rtnl_link	*link = (struct rtnl_link *)obj;
	int					index = rtnl_link_get_ifindex(link);

	fprintf(stderr, "obj: %p  arg: %p\n", obj, arg);
	add_link_to_lua(L, link);
	callback_lua_link(L, index, rtnl_link_get_name(link), "add");
}

/**
 * Initialise the netlink system
 * 
 * @return netlink file handle
 */
int netlink_init() {
	int fd;
	int rc;

	rc = nl_cache_mngr_alloc(NULL, NETLINK_ROUTE, NL_AUTO_PROVIDE, &mngr);
	fprintf(stderr, "rc=%d\n", rc);

	fd = nl_cache_mngr_get_fd(mngr);
	return fd;
}

/**
 * Lua function to watch the netlink "link" activity
 * @arg L			Lua state
 * @arg fid			Function identifier for callback
 *
 * @return			Number of return values (always zero)
 */
int netlink_watch_link(lua_State *L, int fid) {
	int rc;
	int i;
	struct rtnl_link	*link;

	// Create a new global table for the links
	lua_newtable(L);
	lua_setglobal(L, "nl_links");

	// Create a cache manager for links
	rc = nl_cache_mngr_add(mngr, "route/link", (change_func_t)cb_link_dynamic, (void *)L, &cache_link);
	fprintf(stderr, "rc=%d\n", rc);

	// Store our callback function
	fid_link = fid;

	// Iterate over our initial list making sure we add to the Lua table
	nl_cache_foreach(cache_link, cb_link_initial, (void *)L);


	for(i=1; i < 100; i++) {
		link = rtnl_link_get(cache_link, i);
		if(link == NULL) {
			fprintf(stderr, "no more\n");
			break;
		}
		fprintf(stderr, "link detail at index=%d\n", i);
		fprintf(stderr, "  name: %s\n", rtnl_link_get_name(link));
		// Free the reference...
		rtnl_link_put(link);
	}
/*
	while(1) {
		if(nl_cache_mngr_poll(mngr, 1000) > 0) {
			fprintf(stderr, "new stuff\n");
		} else {
			fprintf(stderr, "nothing new\n");
		}
	}
*/

	return 0;
}

int netlink_read(lua_State *L, int fd) {
	int rc;
	fprintf(stderr, "netlink FD=%d\n", fd);

	rc = nl_cache_mngr_data_ready(mngr);	
	fprintf(stderr, "netlink data read=%d\n", rc);

	return 0;
}
