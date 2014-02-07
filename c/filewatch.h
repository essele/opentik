#ifndef _FILEWATCH_H
#define _FILEWATCH_H

#define FW_CHANGE		0
#define	FW_LOG			1
#define FW_DIR			99

int filewatch_init();
int filewatch_add(lua_State *L, int fid, int fd, char *filename, int flags, int fw_type);
int filewatch_remove(int fd, char *filename);
int filewatch_read(lua_State *L, int fd);

#endif
