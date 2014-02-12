#include <stdio.h>
#include <string.h>
#include <stdlib.h> 
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <arpa/inet.h>
#include <netlink/netlink.h>
#include <netlink/cache.h>
#include <netlink/route/rtnl.h>
#include <netlink/route/link.h>
#include <netlink/route/addr.h>
#include "luafuncs.h"
#include "unit_service.h"

/*
 * This module provides basic netlink functionality so that we can 
 * monitor (and ultimately control) link, address and route information
 *
 * We have a unit_service_desc for the service_loop
 */
static struct unit_service_desc		u_svc;

/*
 * We have a cache manager, and then a cache for each type of record,
 * we also store the fid for each type here so we can callback events
 * to Lua
 */
static struct nl_sock		*nls;				// for connection
static struct nl_cache_mngr	*mngr;
static struct nl_cache		*cache_link;
static struct nl_cache		*cache_addr;
static int					nl_cache_fd;		// cache stuff
static int					fid_link_add, fid_link_mod, fid_link_del;
static int					fid_addr_add, fid_addr_mod, fid_addr_del;

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
static void create_flags_hash(lua_State *L, unsigned int flags) {
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
 * Call the callback function for items with change details
 * @arg L			Lua state
 * @arg fid			function id to call
 * @arg action		is it "add", "change" or "delete"
 * @arg link		the link object
 */
static void callback_lua_link(lua_State *L, int fid, struct rtnl_link *link, char *action) {
	int					index = rtnl_link_get_ifindex(link);
	char				buf[256];

	if(fid == 0) return;		// no callback provided

    get_function(L, fid);
    if(!lua_isfunction(L, -1)) {
        fprintf(stderr, "callback_lua_nl: invalid function for callback\n");
        return;
    }
	lua_pushnumber(L, index);
	lua_pushstring(L, rtnl_link_get_name(link));
	lua_pushstring(L, nl_llproto2str(rtnl_link_get_arptype(link), buf, sizeof(buf)));
	lua_pushstring(L, action);
    lua_call(L, 4, 0);
}

/**
 * Helper macros for setting table values for the link
 */
#define	SET_NUM(f,code) lua_pushstring(L,f); lua_pushnumber(L, code); lua_settable(L, -3)
#define	SET_STR(f,code) lua_pushstring(L,f); lua_pushstring(L, code); lua_settable(L, -3)

/**
 * Add/modify link details within the "nl_links" table
 * @arg L			Lua state
 * @arg link		Netlink rtnl_link object
 */
static void add_link_to_lua(lua_State *L, struct rtnl_link *link) {
	unsigned int	flags;
	int				index;
	char			buf[256];

	index = rtnl_link_get_ifindex(link);

	// Get the links table...
	lua_getglobal(L, "nl_links");

	// See if we have the index already... if not, new table
	lua_rawgeti(L, -1, index);
	if(lua_isnil(L, -1)) { lua_pop(L, 1); lua_newtable(L); }
	
	SET_NUM("index", index);
	SET_STR("name", rtnl_link_get_name(link));
	SET_STR("type", nl_llproto2str(rtnl_link_get_arptype(link), buf, sizeof(buf)));
	SET_STR("operstate", rtnl_link_operstate2str(rtnl_link_get_operstate(link), buf, sizeof(buf)));
	SET_STR("mode", rtnl_link_mode2str(rtnl_link_get_linkmode(link), buf, sizeof(buf)));
	SET_STR("addr", nl_addr2str(rtnl_link_get_addr(link), buf, sizeof(buf)));
	SET_STR("bcast", nl_addr2str(rtnl_link_get_broadcast(link), buf, sizeof(buf)));
	SET_NUM("mtu", rtnl_link_get_mtu(link));

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
 * Simple address print routine to convert addresses into text
 */
static char *addr2str(struct nl_addr *addr, char *buf, size_t size) {
	void	*bin;
	int		family;

	if(!addr) { snprintf(buf, size, "none"); return buf; }
	bin = nl_addr_get_binary_addr(addr);
	family = nl_addr_get_family(addr);

	switch(family) {
		case AF_INET:	inet_ntop(AF_INET, bin, buf, size); break;
		case AF_INET6:	inet_ntop(AF_INET6, bin, buf, size); break;
		default:		snprintf(buf, size, "UNKNOWN"); break;
	}
	return buf;
}

/**
 * Add/modify addr details within the "nl_addrs" table
 * @arg L			Lua state
 * @arg addr		Netlink rtnl_addr object
 *
 * TODO: not right yet!
 */
static void add_addr_to_lua(lua_State *L, struct rtnl_addr *addr) {
	char			buf[256];

	// Get the addrs table...
	lua_getglobal(L, "nl_addrs");

	lua_newtable(L);

	// See if we have the index already...
//	lua_rawgeti(L, -1, index);
//	if(lua_isnil(L, -1)) { lua_pop(L, 1); lua_newtable(L); }
	
	SET_NUM("ifindex", rtnl_addr_get_ifindex(addr));
	SET_NUM("family", rtnl_addr_get_family(addr));
	SET_NUM("flags", rtnl_addr_get_flags(addr));
	SET_NUM("prefixlen", rtnl_addr_get_prefixlen(addr));
	SET_STR("scope", rtnl_scope2str(rtnl_addr_get_scope(addr), buf, sizeof(buf)));
	SET_STR("local", addr2str(rtnl_addr_get_local(addr), buf, sizeof(buf)));
	SET_STR("peer", addr2str(rtnl_addr_get_peer(addr), buf, sizeof(buf)));
	SET_NUM("createtime", rtnl_addr_get_create_time(addr));

	// Now set the table at the index...
	int index = lua_objlen(L, -2);
	lua_rawseti(L, -2, index+1);
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

/*
 * This callback is used for any dynamic changes for the link
 * cache (i.e. after the system has started up and got through the
 * initial list)
 */
static void cb_link_dynamic(struct nl_cache *cache, struct nl_object *obj, int action, void *arg) {
	lua_State			*L = (lua_State *)arg;
	struct rtnl_link	*link = (struct rtnl_link *)obj;

	switch(action) {
		case NL_ACT_NEW:
			add_link_to_lua(L, link);
			callback_lua_link(L, fid_link_add, link, "add");
			break;
		case NL_ACT_CHANGE:
			add_link_to_lua(L, link);
			callback_lua_link(L, fid_link_mod, link, "change");
			break;
		case NL_ACT_DEL:
			remove_link_from_lua(L, link);
			callback_lua_link(L, fid_link_del, link, "delete");
			break;
	}
}

/**
 * This is the callback used when iterating over the initial list
 * of interfaces
 */
static void cb_link_initial(struct nl_object *obj, void *arg) {
	lua_State			*L = (lua_State *)arg;
	struct rtnl_link	*link = (struct rtnl_link *)obj;

	add_link_to_lua(L, link);
	callback_lua_link(L, fid_link_add, link, "add");
}

/**
 * Callback for initial interation over the address cache
 */
static void cb_addr_initial(struct nl_object *obj, void *arg) {
	lua_State			*L = (lua_State *)arg;
	struct rtnl_addr	*addr = (struct rtnl_addr *)obj;
	
	fprintf(stderr, "address cache initial: %p\n", obj);
	add_addr_to_lua(L, addr);
}
static void cb_addr_dynamic(struct nl_cache *cache, struct nl_object *obj, int action, void *arg) {
	//lua_State			*L = (lua_State *)arg;

	fprintf(stderr, "address cache dynamic: %p (action=%d)\n", obj, action);
}

/**
 * Rename an interface: we will lookup the old interface then
 * create a change object and action the change
 */
static int netlink_if_rename(lua_State *L) {
	struct rtnl_link	*old, *new;

	char    *oldname = (char *)luaL_checkstring(L, 1);
	char    *newname = (char *)luaL_checkstring(L, 2);

	old = rtnl_link_get_by_name(cache_link, oldname);
	if(!old) {
		fprintf(stderr, "rename failed to find old interface");
		lua_pushnumber(L, 1);
		return 1;
	}
	new = rtnl_link_alloc();
	if(!new) {
		rtnl_link_put(old);
		fprintf(stderr, "unable to create new link object");
		lua_pushnumber(L, 1);
		return 1;
	}
	rtnl_link_set_name(new, newname);
	fprintf(stderr, "about to try change");
	
	int rc = rtnl_link_change(nls, old, new, 0);
	fprintf(stderr, "change returned %d\n", rc);

	rtnl_link_put(old);
	rtnl_link_put(new);

	lua_pushnumber(L, 0);
	return 1;
}

/**
 * Lua function to watch the netlink "link" activity
 * @arg L			Lua state
 * @arg fid			Function identifier for callback
 *
 * @return			Number of return values (always zero)
 */
static int netlink_watch_link(lua_State *L, int fid_add, int fid_mod, int fid_del) {
	int rc;

	// Create a new global table for the links
	lua_newtable(L);
	lua_setglobal(L, "nl_links");

	// Create a cache manager for links
	rc = nl_cache_mngr_add(mngr, "route/link", (change_func_t)cb_link_dynamic, 
														(void *)L, &cache_link);
	fprintf(stderr, "rc=%d\n", rc);

	// Store our callback functions
	fid_link_add = fid_add;
	fid_link_mod = fid_mod;
	fid_link_del = fid_del;

	// Iterate over our initial list making sure we add to the Lua table
	nl_cache_foreach(cache_link, cb_link_initial, (void *)L);

	return 0;
}

/**
 * Lua function to watch the netlink "addr" activity
 * @arg L			Lua state
 * @arg fid			Function identifier for callback
 *
 * @return			Number of return values (always zero)
 */
static int netlink_watch_addr(lua_State *L, int fid_add, int fid_mod, int fid_del) {
	int rc;

	// Create a new global table for the links
	lua_newtable(L);
	lua_setglobal(L, "nl_addrs");

	// Create a cache manager for links
	rc = nl_cache_mngr_add(mngr, "route/addr", (change_func_t)cb_addr_dynamic, 
														(void *)L, &cache_addr);
	fprintf(stderr, "rc=%d\n", rc);

	// Store our callback functions
	fid_addr_add = fid_add;
	fid_addr_mod = fid_mod;
	fid_addr_del = fid_del;

	// Iterate over our initial list making sure we add to the Lua table
	nl_cache_foreach(cache_addr, cb_addr_initial, (void *)L);

	return 0;
}

/*
 * This needs to be called whenever there is data to be read
 * so that we can process waiting notifications
 */
static int netlink_read(lua_State *L, int fd) {
	int rc;
	fprintf(stderr, "netlink FD=%d\n", fd);

	rc = nl_cache_mngr_data_ready(mngr);	
	fprintf(stderr, "netlink data read=%d\n", rc);

	return 0;
}

/*==============================================================================
 * Allow us to monitor netlink related stuff...
 *==============================================================================
 */
static int monitor_netlink(lua_State *L) {
	int		fids[3];
	int		i;

	// Check arguments (netlink type, callback)
	char    *nltype = (char *)luaL_checkstring(L, 1);
	for(i=2; i < 5; i++) {
		fids[i-2] = 0;
		if(lua_isnoneornil(L, i)) continue;
		if(!lua_isfunction(L, i)) return luaL_error(L, "expected function as argument #%d", i);
		lua_pushvalue(L, i);
		fids[i-2] = store_function(L);
	}

	// Do the right thing
	if(strcmp(nltype, "link") ==0 ) {
		netlink_watch_link(L, fids[0], fids[1], fids[2]);
	} else if(strcmp(nltype, "addr") == 0) {
		netlink_watch_addr(L, fids[0], fids[1], fids[2]);
	} else {
		for(i=0; i < 3; i++) free_function(L, fids[i]);
		return luaL_error(L, "unknown netlink type: %s", nltype);
	}
	lua_pushnumber(L, 0);
	return 1;
}

/*==============================================================================
 * Provide our service data for the unit_service module
 *==============================================================================
 */
static int get_service(lua_State *L) {
    u_svc.fd = nl_cache_fd;
    u_svc.read_func = netlink_read;
	u_svc.write_func = NULL;

    lua_pushlightuserdata(L, (void *)&u_svc);
    return 1;
}

/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_reg lib[] = {
	{"monitor_netlink", monitor_netlink},
	{"if_rename", netlink_if_rename},

	// Service descriptor...
	{"get_service", get_service},
	{NULL, NULL}
};

/*------------------------------------------------------------------------------
* Main Library Entry Point ... setup netlink and then intialise all the 
* Lua functions
*------------------------------------------------------------------------------
*/
int luaopen_netlink(lua_State *L) {
	int	rc;

	// Initialise the library...
	luaL_openlib(L, "netlink", lib, 0);

	// Create the netlink cache manager...
	rc = nl_cache_mngr_alloc(NULL, NETLINK_ROUTE, NL_AUTO_PROVIDE, &mngr);
	fprintf(stderr, "rc=%d\n", rc);
	nl_cache_fd = nl_cache_mngr_get_fd(mngr);

	// Create the ad-hoc netlink connection...
	nls = nl_socket_alloc();
	if(!nls) {
		fprintf(stderr, "unable to alloc sock\n");
		return 0;
	}
	if(nl_connect(nls, NETLINK_ROUTE) != 0) {
		fprintf(stderr, "unable to connect\n");
		return 0;
	}
	return 1;
}

