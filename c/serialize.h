#ifndef _SERIALIZE_H
#define _SERIALIZE_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

char *serialize(lua_State *L, int index, int *len);
int unserialize(lua_State *L, char *);

#endif
