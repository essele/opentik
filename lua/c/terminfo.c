#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <ncurses/curses.h>
#include <term.h>
#include <termios.h>
#include <unistd.h>

/*
 * We keep a global reference to our table so we can add all the terminfo
 * values to it
 */
int		table_ref;


/*
 *
 *
 */
static int lua_setupterm(lua_State *L) {
	char 	*term = 0;
	int		i;
	char	*name;

	if (!lua_isnoneornil(L, 1)) term = (char *)luaL_checkstring(L, 1);
	setupterm((char *)term, 1, (int *)0);

	/*
	 * Now populate the table with strings, bools and nums
	 */
	lua_rawgeti(L, LUA_REGISTRYINDEX, table_ref);

	// Strings
	for (i=0; (name = strnames[i]); i++) {
		char *strval = tigetstr(name);
		if (strval) {
			lua_pushstring(L, strval);
			lua_setfield(L, -2, strfnames[i]);
		}
	}
	// Bools
	for (i=0; (name = boolnames[i]); i++) {
		if (tigetflag(name)==1) {
			lua_pushboolean(L, true);
			lua_setfield(L, -2, boolfnames[i]);
		}
	}		
	// Nums
	for (i=0; (name = numnames[i]); i++) {
		int val = tigetnum(name);
		if (val >= 0) {
			lua_pushnumber(L, val);
			lua_setfield(L, -2, numfnames[i]);
		}
	}
	return 1;
}

/*
static int cindex(lua_State *L) {
	fprintf(stderr, "HERE\n");

	char *s = tigetstr("kcub1");
	fprintf(stderr, "s=%p\n", s);

	lua_pushstring(L, "fred");
	return 1;
}
*/

/*
 * out - output characters, if we supply any arguments then we assume
 * it's a tparm and we hack a 9 arg version to deal with varargs
 *
 * otherwise we just use putp
 */
static int out(lua_State *L) {
	int arg[9];
	int i;
	char *str = (char *)luaL_checkstring(L, 1);

	if (lua_isnoneornil(L, 2)) {
		// Simple string output
		putp(str);
		return 0;
	}
	for (i=0; i < 9; i++) {
		if (lua_isnumber(L, 2+i)) {
			arg[i] = lua_isnumber(L, i+2) ? (int)lua_tointeger(L, i+2) : 0;
		}
	}
	putp(tparm(str, arg[0], arg[1], arg[2], arg[3], arg[4], arg[5], arg[6], arg[7], arg[8]));
	return 0;
}



/*
 * Set terminal to raw state, saving prior state for later restore
 */
struct termios saved_termios;

static int term_raw(lua_State *L) {
	int				rc;
	struct termios 	tios;

	putp(tparm(keypad_xmit));

	rc = tcgetattr(0, &saved_termios);
	if (rc != 0) luaL_error(L, "unable to tcgetattr: %d", rc);
	memcpy(&tios, &saved_termios, sizeof(struct termios));
	
	tios.c_lflag &= ~(ECHO|ICANON);
	rc = tcsetattr(0, TCSANOW, &tios);
	if (rc != 0) luaL_error(L, "unable to tcsetattr: %d", rc);
	return 0;
}
static int term_restore(lua_State *L) {
	int rc;

	rc = tcsetattr(0, TCSANOW, &saved_termios);
	
	putp(tparm(keypad_local));
	if (rc != 0) luaL_error(L, "unable to tcsetattr: %d", rc);
	return 0;
}

/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_Reg lib[] = {
	{"setupterm", lua_setupterm},
	{"term_raw", term_raw},
	{"term_restore", term_restore},
	{"out", out},
    {NULL, NULL}
};

/*------------------------------------------------------------------------------
 * Main Library Entry Point ... just intialise all the functions
 *------------------------------------------------------------------------------
 */
int luaopen_term(lua_State *L) {
//    luaL_openlib(L, "lee", lib, 0);
	luaL_newlib(L, lib);

	// The top of the stack is our table, so keep a reference, but it pops so
	// we have to duplicate
	lua_pushvalue(L, -1);
	table_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	fprintf(stderr, "REF=%d\n", table_ref);
/*
	lua_createtable(L, 0, 0);
	lua_createtable(L, 0, 0);
	lua_pushcfunction(L, cindex);
	lua_setfield(L, -2, "__index");
	lua_setmetatable(L, -2);
	lua_pushstring(L, "1");
	lua_setfield(L, -2, "one");
	lua_setfield(L, -2, "bill");
*/
    return 1;
}

