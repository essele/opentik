#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netlink/netlink.h>
#include <netlink/cache.h>
#include <netlink/route/link.h>
#include <netlink/socket.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>


/*==============================================================================
 * There are a few important globals that are setup by the libary initialisation
 * function to ensure ease of use for the rest of the functions
 *==============================================================================
 */

struct nl_sock			*nls;				// netlink socket
struct nl_cache_mngr	*cache_mngr;		// manager for our stuff

void callback_link(struct nl_cache *cache, struct nl_object *object, int i, void *data);

struct int_cache {
	lua_State			*L;
	struct nl_cache		*cache;
	int					cb_id;
	change_func_t		cb;
	const char			*name;
} cache_list[] = { 
	{ NULL, NULL, 0, callback_link, "route/link" }, 
	{ NULL, NULL, 0, NULL, "route/route" },
	{ NULL, NULL, 0, NULL, "route/address" },
	{ NULL, NULL, 0, NULL },
};
	
/*------------------------------------------------------------------------------
 * Helper function for keeping track of our function callbacks
 *------------------------------------------------------------------------------
 */
static inline int store_function(lua_State *L) {
    if(!lua_isfunction(L, -1)) return 0;
    return(luaL_ref(L, LUA_REGISTRYINDEX));
}
static inline void get_function(lua_State *L, int id) {
    lua_rawgeti(L, LUA_REGISTRYINDEX, id);
}
static inline void free_function(lua_State *L, int id) {
    luaL_unref(L, LUA_REGISTRYINDEX, id);
}

/*------------------------------------------------------------------------------
 * Setup the basic netlink structures and cache manager
 *------------------------------------------------------------------------------
 */
int netlink_init() {
	int			rc;

	// Create the main netlink socket
	nls = nl_socket_alloc();
	if (!nls) {
		fprintf(stderr, "unable to create netlink socket\n");
		return -1;
	}
	
	// Create the cache manager
	rc = nl_cache_mngr_alloc(nls, AF_UNSPEC, 0, &cache_mngr);
	if (rc < 0) {
		fprintf(stderr, "unable to create cache manager: rc=%d\n", rc);
		return -1;
	}
	return 0;
}

/*------------------------------------------------------------------------------
 * Handle the callback for link ... build a suitable table and call the lua
 * callback
 *------------------------------------------------------------------------------
 */
void callback_link(struct nl_cache *cache, struct nl_object *object, int i, void *data) {
	struct int_cache	*cp = (struct int_cache *)data;
	lua_State			*L = cp->L;
	struct rtnl_link *link = (struct rtnl_link *)object;
	
	printf("lua_State = %p\n", L);

	printf("Change called link cache=%p obj=%p i=%d data=%p\n", cache, object, i, data );
	printf("Link object=%p\n", link);

	

	// Execute the lua callback...
	get_function(L, cp->cb_id);
	if(!lua_isfunction(L, -1)) return; // TODO error?


	lua_newtable(L);
	lua_pushstring(L, "lee");
	lua_setfield(L, -2, "fred");
	lua_pushstring(L, "is joe");
	lua_setfield(L, -2, "joe");

//	lua_pushstring(L, "hello");
	lua_call(L, 1, 0);
}


/*------------------------------------------------------------------------------
 * Add a cache, setup the callback, call the callback for each initial entry
 *------------------------------------------------------------------------------
 */
static int add_cache(lua_State *L) {
	if(!lua_isstring(L, 1)) return luaL_error(L, "expected string as first argument");
	if(!lua_isfunction(L, 2)) return luaL_error(L, "expected function as second argument");

	int					rc;
	const char			*type = lua_tolstring(L, 1, NULL);
	struct int_cache	*cp = cache_list;
	struct nl_object	*obj;

	// See if we can find the cache info...
	while(cp->name) {
		if(strcmp(cp->name, type) == 0) {
			printf("Found a match for %s\n", cp->name);
			break;
		}
		cp++;
	}
	if(!cp->name) return luaL_error(L, "unknown cache type: %s", type);

	// Update the cache list and store the lua callback function...
	lua_pushvalue(L, 2);
	cp->L = L;
	cp->cb_id = store_function(L);
	rc = nl_cache_mngr_add(cache_mngr, cp->name, cp->cb, (void *)cp, &cp->cache);

	// Now run through the initial list and call the callback for each
	obj = nl_cache_get_first(cp->cache);
	while(obj) {
		printf("Obj found\n");
		cp->cb(cp->cache, obj, 1, (void *)cp);
		obj = nl_cache_get_next(obj);
	}


	



	// Register the cache...
//	rc = nl_cache_mngr_add(cache_mngr, type, cb, (void *)L, &cache);
//	printf("c=%d\n", c);	

	// Execure the function
//	get_function(L, id);
//	if(!lua_isfunction(L, -1)) return luaL_error(L, "function call problems");
//	lua_pushstring(L, "hello");
//	lua_call(L, 1, 0);

	// Return 0
	lua_pushnumber(L, 0);	
	return 1;
}


//	c = nl_cache_mngr_add(cache_mgr, "route/link", change_func, (void *)45, &link_cache);




void change_func(struct nl_cache *cache, struct nl_object *object, int i, void *data) {
	struct rtnl_link *link = (struct rtnl_link *)object;

	printf("Change called cache=%p obj=%p i=%d data=%p\n", cache, object, i, data );

	// We probably want to ignore lo, and the dummy entries...
	//
	// lo
	// gre0
	// gretap0
	// tunl0
	//

	if (i == 1) {
		printf("NEW\n");
	} else if (i == 2) {
		printf("DEL\n");
	} else if (i == 5) {
		printf("CHANGE\n");
	} else {
		printf("UNKNOWN\n");
	}
	
	printf("Name is [%s]\n", rtnl_link_get_name(link));
	printf("Type is [%s]\n", rtnl_link_get_type(link));
	printf("ArpType is [%d]\n", rtnl_link_get_arptype(link));

	//
	// Here we would callback lua so we can update our internal
	// state
	//
	// on links ... add or remove as needed, rerun the config match
	//              we don't need to do anything with routes as any changes
	//              will force the routes to update and cause a config match there
	//
}



int main(int argc, char *argv[]) {
	struct nl_sock		*nls;
	int					c;
	struct nl_cache		*link_cache;

	printf("Hello world!\n");


	nls = nl_socket_alloc();
	printf("nls=%p\n", nls);


//	c = rtnl_link_alloc_cache(nls, AF_UNSPEC, &link_cache);
//	printf("c=%d\n", c);

	struct nl_cache_mngr	*cache_mgr;

	c = nl_cache_mngr_alloc(nls, AF_UNSPEC, 0, &cache_mgr);
	printf("c=%d\n", c);	

//	struct nl_cache		*route_cache;

	c = nl_cache_mngr_add(cache_mgr, "route/link", change_func, (void *)45, &link_cache);
	printf("c=%d\n", c);	
	printf("cache = %p\n", link_cache);

	printf("Items=%d\n", nl_cache_nitems(link_cache));

	// Run our callback for the initial set...
	struct nl_object *obj;
	
	obj = nl_cache_get_first(link_cache);
	while(obj) {
		printf("Obj found\n");
		change_func(link_cache, obj, 1, (void *)1234);
		obj = nl_cache_get_next(obj);
	}



	while(1) {
		c = nl_cache_mngr_poll(cache_mgr, 1000);
		printf("poll c=%d\n", c);
	}

	exit(0);
}

/*
 * Dummy function
 */
static int dummy(lua_State *L) {
	printf("DUMMY\n");
	return 0;
}

/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_Reg lib[] = {
    {"dummy", dummy},
	{"add_cache", add_cache},
    {NULL, NULL}
};

/*------------------------------------------------------------------------------
 * Main Library Entry Point ... just intialise all the functions
 *------------------------------------------------------------------------------
 */
int luaopen_lee(lua_State *L) {
//    luaL_openlib(L, "lee", lib, 0);
	luaL_newlib(L, lib);

	netlink_init();
    return 1;
}

