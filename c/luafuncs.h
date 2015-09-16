#ifndef _LUAFUNCS_H
#define _LUAFUNCS_H

/*==============================================================================
 * Helper functions for adding, removing and calling function references
 *==============================================================================
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

#endif
