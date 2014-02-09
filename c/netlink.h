#ifndef _NETLINK_H
#define _NETLINK_H

int netlink_init();
int netlink_watch_link(lua_State *L, int fid);
int netlink_read(lua_State *L, int fd);

#endif
