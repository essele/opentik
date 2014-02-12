#ifndef _NETLINK_H
#define _NETLINK_H

int netlink_init();
int netlink_watch_link(lua_State *L, int fid_add, int fid_mod, int fid_del);
int netlink_watch_addr(lua_State *L, int fid_add, int fid_mod, int fid_del);
int netlink_read(lua_State *L, int fd);

int netlink_if_rename(lua_State *L);

#endif
