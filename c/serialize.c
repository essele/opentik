#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>



/*==============================================================================
 *
 * Utility functions to handle a growing string buffer, this is similar to the
 * Lua_Buffer concept, but should be quicker where we don't need to convert back
 * to a lua variable
 *
 *==============================================================================
 */
#define BUF_INC		2048
#define MAXNUMLEN	32

struct charbuf {
	char	*p;
	int		alloc;
	int		free;
};

struct charbuf *charbuf_new() {
	struct charbuf *b = malloc(sizeof(struct charbuf));
	b->p = malloc(BUF_INC);
	b->alloc = BUF_INC;
	b->free = BUF_INC;
	return(b);
}
void charbuf_free(struct charbuf *b) {
	free(b->p);
	free(b);
}
void inline charbuf_make_space(struct charbuf *b, int need) {
	while(b->free < need) {
		b->alloc += BUF_INC; b->free += BUF_INC;
		b->p = realloc(b->p, b->alloc);
	}
}
void charbuf_addstring(struct charbuf *b, char *d, int len) {
	if(!len) len = strlen(d);
	charbuf_make_space(b, len);
	memcpy(b->p+(b->alloc-b->free), d, len);
	b->free -= len;
}
void charbuf_addchar(struct charbuf *b, char c) {
	charbuf_make_space(b, 1);
	b->p[b->alloc-b->free] = c;
	b->free--;
}
void charbuf_addnumber(struct charbuf *b, double num) {
	charbuf_make_space(b, MAXNUMLEN);
	b->free -= sprintf(&b->p[b->alloc-b->free], "%.14g", num);
}
/* Note, the string will need freeing */
char *charbuf_tostring(struct charbuf *b, int *len) {
	char	*p = b->p;

	if(!len) 
		charbuf_addchar(b, '\0');
	else
		*len = b->alloc-b->free;
	free(b);
	return p;
}

/*==============================================================================
 * Given an index into the stack (i.e. a variable) we will serialize the data
 * into a form that resembles lua "dostring'd" format.
 *
 * We use a charbuf to concat the string
 *==============================================================================
 */
int serialize_variable(lua_State *L, int index, struct charbuf *b) {
	const char	*p;
	size_t		len;
	int		type = lua_type(L, index);
	int		first = 1;

	switch(type) {
	case LUA_TBOOLEAN:
		charbuf_addstring(b, (lua_toboolean(L, index) ? "true" : "false"), 0);
		break;
	case LUA_TNUMBER:
		charbuf_addnumber(b, lua_tonumber(L, index));
		break;
	case LUA_TSTRING:
		charbuf_addchar(b, '"');
		// We need to quote quotes...
		p = lua_tolstring(L, index, &len);
		while(len--) {
			switch(*p) {
			case '\"':
			case '\\':
			case '\n':
				charbuf_addchar(b, '\\');
				charbuf_addchar(b, *p++);
				break;
			case '\0':
				charbuf_addstring(b, "\\000", 4);
				p++;
				break;
			default:
				charbuf_addchar(b, *p++);
				break;
			}
		}
		charbuf_addchar(b, '"');
		break;
	case LUA_TTABLE:
		charbuf_addchar(b, '{');
		lua_pushnil(L);
		if(index < 0) index--;	// allow for the extra pushnil if we are negative
		while(lua_next(L, index) != 0) {
			if(first) 
				first = 0;
			else
				charbuf_addchar(b, ',');

			charbuf_addchar(b, '[');
			serialize_variable(L, -2, b);
			charbuf_addchar(b, ']');
			charbuf_addchar(b, '=');
			serialize_variable(L, -1, b);
			lua_pop(L, 1);
		}
		charbuf_addchar(b, '}');
		break;
	}
	return 0;
}

/*==============================================================================
 * This is the main serialize wraper function that creates the buffer and
 * and calls serialize_variable
 *==============================================================================
 */
char *serialize(lua_State *L, int index, int *len) {
	struct charbuf	*b = charbuf_new();

	serialize_variable(L, index, b);
//	lua_pushlstring(L, b->p, b->alloc-b->free);
//	charbuf_free(b);
	return charbuf_tostring(b, len);
}

/*==============================================================================
 * Push a copy of the string without the escapes... (remove single backslashes)
 *==============================================================================
 */
void lua_pushcleanlstring(lua_State *L, char *p, int len) {
	char *s = malloc(len);
	char *d = s;
	int i;

	for(i=0; i<len; i++) {
		if(*p == '\\') p++;
		*d++ = *p++;
	}
	lua_pushlstring(L, s, len);
	free(s);
}

/*==============================================================================
 * Unserialize a variable based on the lua string, we parse
 * manually to avoid code exploits
 *==============================================================================
 */
int unserialize_variable(lua_State *L, char **str) {
	char		*p = *str;
	char 		*e;
	int			len = 0;
	int			copyflag = 0;

	if(*p == '\"') {
		e = (char *)++p;		// first char of string
		while(*e != '\"') {
			if(!*e) { *str = 0; return 0; }
			if(*e == '\\') { e++; copyflag=1; }
			e++; len++;
		}
		// now we know how long the string is... we copy if we have to edit...
		(copyflag ? lua_pushcleanlstring(L, p, len) : lua_pushlstring(L, p, len));
		*str=++e;
		return 1;
	} else if(*p == '{') {
		// We are a table, we should have keys with [], and values in the clear
		lua_newtable(L);
		while(*++p != '}') {
			if(*p++ != '[' || !*p || !unserialize_variable(L, &p)) 
				{ lua_pop(L, 1); *str = 0; return 0; } 
			if(*p++ != ']' || !*p || *p++ != '=' || !*p || !unserialize_variable(L, &p)) 
				{ lua_pop(L, 2); *str = 0; return 0; }
			lua_rawset(L, -3);
			if(*p != ',') break;
		}
		if(*p != '}') { lua_pop(L, 1); *str = 0; return 0; }
		*str = ++p;
		return 1;
	} else if(*p == 't' || *p == 'f') {
		if(strncmp(p, "true", 4) == 0) {
			lua_pushboolean(L, 1);
			*str = p+4;
		} else if(strncmp(p, "false", 5) == 0) {
			lua_pushboolean(L, 0);
			*str = p+5;
		}
		return 1;
	} else {
		// We assume a number at this point... find the first non-number char...
		len = strspn(p, "0123456789.-");
		if(!len) { return 0; }
		lua_pushlstring(L, p, len);
		*str = (char *)p+len;
		return 1;
	}
	return 0;
}

/*==============================================================================
 * We go through a string and turn it back into the appropriate
 * variable. We need to copy the string since we will mess about
 * with it if it has escapes in it.
 *==============================================================================
 */
int unserialize(lua_State *L, char *p) {
//	char	*p = (char *)lua_tostring(L, 1);
	return unserialize_variable(L, &p);
}


