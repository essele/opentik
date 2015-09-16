#include <stdio.h>
#include <string.h>
#include <stdlib.h> 
#include <errno.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <arpa/inet.h>
#include <netinet/ip.h>
#include <net/if_arp.h>
#include <netlink/netlink.h>
#include <netlink/cache.h>
#include <netlink/route/rtnl.h>
#include <netlink/route/link.h>
#include <netlink/route/addr.h>

#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>

#include <linux/sockios.h>
#include <linux/if_tunnel.h>

#include "netlink.h"
#include "luafuncs.h"
#include "unit.h"

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
static int					dgram_fd;			// for tunnel stuff
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

/*
 * Handy macro to make code easier to read
 */
#define IS(i,v)	(strcmp(i,v)==0)


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
			lua_pushboolean(L, 1);
			lua_rawset(L, -3);
		}
		mask <<= 1;
	}
}

/**
 * Helper macros for setting table values for the link
 */
#define	SET_NUM(f,code) lua_pushstring(L,f); lua_pushnumber(L, code); lua_settable(L, -3)
#define	SET_STR(f,code) lua_pushstring(L,f); lua_pushstring(L, code); lua_settable(L, -3)

/**
 * Simple address print routine to convert addresses into text
 */
static char *addr2str(struct nl_addr *addr, int prefix, char *buf, size_t size) {
	void	*bin;
	int		family, l;

	if(!addr) { snprintf(buf, size, "none"); return buf; }
	bin = nl_addr_get_binary_addr(addr);
	family = nl_addr_get_family(addr);

	switch(family) {
		case AF_INET:	inet_ntop(AF_INET, bin, buf, size); break;
		case AF_INET6:	inet_ntop(AF_INET6, bin, buf, size); break;
		default:		snprintf(buf, size, "UNKNOWN"); break;
	}
	if(prefix) {
		l = strlen(buf);
		snprintf(buf+l, sizeof(buf)-l, "/%d", prefix);
	}
	return buf;
}

/*
 * This callback is used for any dynamic changes for the link
 * cache (i.e. after the system has started up and got through the
 * initial list)
 */
static void cb_link_dynamic(struct nl_cache *cache, struct nl_object *obj, int action, void *arg) {
	lua_State			*L = (lua_State *)arg;
	struct rtnl_link	*link = (struct rtnl_link *)obj;
	unsigned int		flags;
	int					fid = 0;
	char				buf[256];
	char				*actstr;

	switch(action) {
		case NL_ACT_NEW: 		fid = fid_link_add; actstr="add"; break;
		case NL_ACT_CHANGE: 	fid = fid_link_mod; actstr="change"; break;
		case NL_ACT_DEL: 		fid = fid_link_del; actstr="delete"; break;
	}

	if(fid == 0) return;		// no callback provided
    get_function(L, fid);
    if(!lua_isfunction(L, -1)) {
        fprintf(stderr, "%s: invalid function for callback (action=%d)\n", __func__, action);
		return;
    }

	// Now we push interface name, proto
	lua_pushstring(L, rtnl_link_get_name(link));
	lua_pushstring(L, nl_llproto2str(rtnl_link_get_arptype(link), buf, sizeof(buf)));

	// Now the interface object
	lua_newtable(L);
	SET_NUM("index", rtnl_link_get_ifindex(link));
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

	// And the "action"
	lua_pushstring(L, actstr);

	// And call the callback...
    lua_call(L, 4, 0);
}

/**
 * For the initial loop round they will all be "new"
 */
static void cb_link_initial(struct nl_object *obj, void *arg) {
	cb_link_dynamic(NULL, obj, NL_ACT_NEW, arg );
}

/**
 * Callback for the interation over the address cache
 */
static void cb_addr_dynamic(struct nl_cache *cache, struct nl_object *obj, int action, void *arg) {
	lua_State			*L = (lua_State *)arg;
	struct rtnl_addr	*addr = (struct rtnl_addr *)obj;
	struct rtnl_link	*link = NULL;
	int					index;
	int					fid = 0;
	char				buf[256];
	char				*actstr;

	// We need to interface index so we can get the name...
	index = rtnl_addr_get_ifindex(addr);
	if(rtnl_link_get_kernel(nls, index, NULL, &link) != 0) {
		fprintf(stderr, "%s: unable to get interface (idx=%d)\n", __func__, index);
		goto finish;
	}
	
	switch(action) {
		case NL_ACT_NEW: 		fid = fid_addr_add; actstr="add"; break;
		case NL_ACT_CHANGE: 	fid = fid_addr_mod; actstr="change"; break;
		case NL_ACT_DEL: 		fid = fid_addr_del; actstr="delete"; break;
	}
	
	if(fid == 0) goto finish;		// no callback provided
    get_function(L, fid);
    if(!lua_isfunction(L, -1)) {
        fprintf(stderr, "%s: invalid function for callback (action=%d)\n", __func__, action);
        goto finish;
    }

	// Now push the args... ip/prefix and interfacename
	lua_pushstring(L, addr2str(rtnl_addr_get_local(addr), rtnl_addr_get_prefixlen(addr), buf, sizeof(buf)));
	lua_pushstring(L, link ? rtnl_link_get_name(link) : "unknown");

	// Now we create the table for the details
	lua_newtable(L);
	SET_NUM("ifindex", rtnl_addr_get_ifindex(addr));
	SET_NUM("family", rtnl_addr_get_family(addr));
	SET_NUM("flags", rtnl_addr_get_flags(addr));
	SET_NUM("prefixlen", rtnl_addr_get_prefixlen(addr));
	SET_STR("scope", rtnl_scope2str(rtnl_addr_get_scope(addr), buf, sizeof(buf)));
	SET_STR("local", addr2str(rtnl_addr_get_local(addr), 0, buf, sizeof(buf)));
	SET_STR("peer", addr2str(rtnl_addr_get_peer(addr), 0, buf, sizeof(buf)));
	SET_NUM("createtime", rtnl_addr_get_create_time(addr));

	// And the "action"
	lua_pushstring(L, actstr);

	// And call the callback...
    lua_call(L, 4, 0);

finish:
	if(link) rtnl_link_put(link);
}
/*
 * For the initial loop round they will all be "new"
 */
static void cb_addr_initial(struct nl_object *obj, void *arg) {
	cb_addr_dynamic(NULL, obj, NL_ACT_NEW, arg);
}

/*
 * For tunnel devices the first one (i.e. gre0) is the master devices that can't be used
 * for a tunnel but it used to create all the others. We need to probe to get it, then
 * rename it so we can use gre0 as a real tunnel.
 */
int tunnel_probe_and_rename(lua_State *L) {
	struct rtnl_link		*old = NULL, *new = NULL;
	int						rval = 0, rc;
	struct ip_tunnel_parm   tp;
	struct ifreq			ifr;
	char					base_device[IFNAMSIZ], 	new_device[IFNAMSIZ];
	char					*type = (char *)luaL_checkstring(L, 1);

	snprintf(base_device, IFNAMSIZ, "%s0", type);
	snprintf(new_device, IFNAMSIZ, "__%s", type);

	// We first check to see if we already have new_device (i.e. __gre)
	if(rtnl_link_get_kernel(nls, 0, new_device, &old) == 0) {
		rtnl_link_put(old);
		lua_pushnumber(L, 1); 
		return 1;
	}

	// Setup the structures ready to probe the interface...
	memset(&tp, 0, sizeof(struct ip_tunnel_parm));
	strcpy(ifr.ifr_name, base_device);
	ifr.ifr_ifru.ifru_data = (void *)&tp;
	
	// Do the actual probe...
	if(ioctl(dgram_fd, SIOCGETTUNNEL, &ifr) != 0) {
		fprintf(stderr, "%s: unable to SIOCGETTUNNEL (errno=%d)\n", __func__, errno); 
		goto finish;
	}

	// Now see if we have gre0 as a non-pointopoint...
	if(rtnl_link_get_kernel(nls, 0, base_device, &old) != 0) {
		fprintf(stderr, "%s: gre0 does not exist, this really doesn't make sense\n", __func__);
		goto finish;
	}
	if(rtnl_link_get_flags(old) & IFF_POINTOPOINT) {
		fprintf(stderr, "%s: gre0 is a pointopoint interface, aaarrrggghh!\n", __func__);
		goto finish;
	}

	// Allocate a new link to change the name...
	if(!(new = rtnl_link_alloc())) {
		fprintf(stderr, "%s: unable to create new link object\n", __func__);
		goto finish;
	}

	// Set the naem, and action the change...
	rtnl_link_set_name(new, new_device);
	
	if(!(rc = rtnl_link_change(nls, old, new, 0))) {
		fprintf(stderr, "change returned %d\n", rc);
		goto finish;
	}
	rval = 1;

finish:
	// Free the objects...
	if(old) rtnl_link_put(old);
	if(new) rtnl_link_put(new);

	// Return...
	lua_pushnumber(L, rval);	
	return 1;
}

/*
 * To create a tunnel we need a name, a type, local and remote addresses 
 * and some flags
 */
int tunnel_create(lua_State *L) {
    int                     rc;
    struct ip_tunnel_parm   tp, *p = &tp;
    struct ifreq            ifr;

	char					*name = (char *)luaL_checkstring(L, 1);
	char					*type = (char *)luaL_checkstring(L, 2);
	char					*local = (char *)luaL_checkstring(L, 3);
	char					*remote = (char *)luaL_checkstring(L, 4);

	// Clear out and setup our structure...
    memset(p, 0, sizeof(struct ip_tunnel_parm));
    ifr.ifr_ifru.ifru_data = (void *)p;

	// Populate based on type...	
	if(IS(type, "gre")) {
		strcpy(ifr.ifr_name, "__gre");
		p->iph.protocol = IPPROTO_GRE;
	} else if(IS(type, "ipip")) {
		strcpy(ifr.ifr_name, "__ipip");
		p->iph.protocol = IPPROTO_IPIP;
	} else 
		return luaL_error(L, "unknown tunnel type: %s", type);
	
	// Generic settings...
	p->iph.version = 4;
	p->iph.ihl = 5;
	p->iph.frag_off = htons(IP_DF);

	// The name and addresses...
	strcpy(p->name, name);
	p->iph.saddr = inet_addr(local);
	p->iph.daddr = inet_addr(remote);

	// Do it...
    if((rc = ioctl(dgram_fd, SIOCADDTUNNEL, &ifr)) != 0) {
		fprintf(stderr, "tunnel_create: ioctl SIOCADDTUNNEL failed (rc=%d)\n", rc);
		lua_pushnumber(L, 0);
		return 1;
	}
	// We succeeded
	lua_pushnumber(L, 1);
	return 1;
}

int tunnel_delete(lua_State *L) {
    int                     rc;
    struct ip_tunnel_parm   tp, *p = &tp;
    struct ifreq            ifr;
	char					*name = (char *)luaL_checkstring(L, 1);

	// Clear out and setup our structure...
    memset(p, 0, sizeof(struct ip_tunnel_parm));
    ifr.ifr_ifru.ifru_data = (void *)p;

	// Set the name, ready for delete
	strcpy(ifr.ifr_name, name);
	strcpy(p->name, name);

	// Do it...
    if((rc = ioctl(dgram_fd, SIOCDELTUNNEL, &ifr)) != 0) {
		fprintf(stderr, "%s: ioctl SIOCDELTUNNEL failed (rc=%d, errno=%d)\n", __func__, rc, errno);
		lua_pushnumber(L, 0);
		return 1;
	}
	// We succeeded
	lua_pushnumber(L, 1);
	return 1;
}

/**
 * Given an ipaddress and an interface we build an rtnl_addr
 * structure that we can use for adds, changes or deletes.
 */
static struct rtnl_addr *create_addr(char *ip, char *iface) {
	struct nl_addr			*ipaddr = NULL;
	struct rtnl_addr		*addr = NULL;
	struct rtnl_link		*link = NULL;

	// First we find the interface (link)
	if(rtnl_link_get_kernel(nls, 0, iface, &link) != 0) {
		fprintf(stderr, "%s: unable to find link %s", __func__, iface);
		goto finish;
	}

	// Now we attempt to parse the IP address
	if(nl_addr_parse(ip, AF_UNSPEC, &ipaddr) != 0) {
		fprintf(stderr, "%s: nl_addr_parse(%s) failed\n", __func__, ip);
		goto finish;
	}

	// Create the address
	addr = rtnl_addr_alloc();
	if(!addr) {
		fprintf(stderr, "%s: rtnl_addr_alloc() failed\n", __func__);
		goto finish;
	}

	// Set the link and address
	rtnl_addr_set_link(addr, link);
	rtnl_addr_set_local(addr, ipaddr);

finish:
	if(ipaddr) nl_addr_put(ipaddr);
	if(link) rtnl_link_put(link);
	
	return addr;
}

/**
 * Add an address to an interface
 * 
 * takes a.b.c.d or a.b.c.d/pp
 */
static int addr_add(lua_State *L) {
	char					*ip = (char *)luaL_checkstring(L, 1);
	char					*iface = (char *)luaL_checkstring(L, 2);
	struct rtnl_addr		*addr = NULL;
	int						rval = 0;

	if(!(addr = create_addr(ip, iface))) goto finish;
	
	// New we add the address
	if(rtnl_addr_add(nls, addr, 0) != 0) {
		fprintf(stderr, "%s: unable to rtnl_addr_add\n", __func__);
		goto finish;
	}
	rval = 1;

finish:
	if(addr) rtnl_addr_put(addr);
	lua_pushnumber(L, rval); 
	return 1;
}

/**
 * Remove an address from an interface
 */
static int addr_remove(lua_State *L) {
	char					*ip = (char *)luaL_checkstring(L, 1);
	char					*iface = (char *)luaL_checkstring(L, 2);
	struct rtnl_addr		*addr = NULL;
	int						rval = 0;

	if(!(addr = create_addr(ip, iface))) goto finish;
	
	// New we delete the address
	if(rtnl_addr_delete(nls, addr, 0) != 0) {
		fprintf(stderr, "%s: unable to rtnl_addr_delete\n", __func__);
		goto finish;
	}
	rval = 1;

finish:
	if(addr) rtnl_addr_put(addr);
	lua_pushnumber(L, rval); 
	return 1;
}

/**
 * Set an interface value (inc. up and down)
 */
static int if_set(lua_State *L) {
	struct rtnl_link	*delta = rtnl_link_alloc();
	struct rtnl_link	*intf = NULL;
	char				*interface = (char *)luaL_checkstring(L, 1);
	char				*item = (char *)luaL_checkstring(L, 2);
	int					rc = 0;

	if(rtnl_link_get_kernel(nls, 0, interface, &intf) != 0) {
		fprintf(stderr, "%s: cant get interface details: %s\n", __func__, interface);
		goto finish;
	}
	if(!delta) return luaL_error(L, "%s: unable to rtnl_link_alloc()", __func__);

	if(IS(item, "up")) {
		rtnl_link_set_flags(delta, IFF_UP);
	} else if(IS(item, "down")) {
		rtnl_link_unset_flags(delta, IFF_UP);
	} else if(IS(item, "mtu")) {
		rtnl_link_set_mtu(delta, luaL_checkint(L, 3));
	} else if(IS(item, "name")) {
		rtnl_link_set_name(delta, luaL_checkstring(L, 3));
	}

	// Make the change...
	if(rtnl_link_change(nls, intf, delta, 0) != 0) {
		fprintf(stderr, "%s: unable to make interface change\n", __func__);
		goto finish;
	}
	rc = 1;

finish:
	// Free the objects...
	if(intf) rtnl_link_put(intf);
	if(delta) rtnl_link_put(delta);

	// Push the result and return...
	lua_pushnumber(L, rc);
	return 1;
}


/**
 * Rename an interface: we will lookup the old interface then
 * create a change object and action the change
 *
 * TODO: If the interface is up, then we need to take it down before
 *	   we attempt a rename.
 */
static int netlink_if_rename(lua_State *L) {
	struct rtnl_link	*old, *new;

	char	*oldname = (char *)luaL_checkstring(L, 1);
	char	*newname = (char *)luaL_checkstring(L, 2);

	old = rtnl_link_get_by_name(cache_link, oldname);
	if(!old) {
		fprintf(stderr, "%s: failed to find old interface", __func__);
		lua_pushnumber(L, 1);
		return 1;
	}
	new = rtnl_link_alloc();
	if(!new) {
		rtnl_link_put(old);
		fprintf(stderr, "%s: unable to create new link object", __func__);
		lua_pushnumber(L, 1);
		return 1;
	}
	rtnl_link_set_name(new, newname);
	
	int rc = rtnl_link_change(nls, old, new, 0);
	if(rc != 0) fprintf(stderr, "%s: rtnl_link_change returned %d\n", __func__, rc);

	rtnl_link_put(old);
	rtnl_link_put(new);

	// TODO: rc
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
static int watch_netlink(lua_State *L) {
	int		fids[3];
	int		i;

	// Check arguments (netlink type, callback)
	char	*nltype = (char *)luaL_checkstring(L, 1);
	for(i=2; i < 5; i++) {
		fids[i-2] = 0;
		if(lua_isnoneornil(L, i)) continue;
		if(!lua_isfunction(L, i)) return luaL_error(L, "expected function as argument #%d", i);
		lua_pushvalue(L, i);
		fids[i-2] = store_function(L);
	}

	// Do the right thing
	if(IS(nltype, "link")) {
		netlink_watch_link(L, fids[0], fids[1], fids[2]);
	} else if(IS(nltype, "addr")) {
		netlink_watch_addr(L, fids[0], fids[1], fids[2]);
	} else {
		for(i=0; i < 3; i++) free_function(L, fids[i]);
		return luaL_error(L, "unknown netlink type: %s", nltype);
	}
	lua_pushnumber(L, 0);
	return 1;
}


/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_reg lib[] = {
	{"watch", watch_netlink},
	{"if_rename", netlink_if_rename},
	{"if_set", if_set},
	{"addr_add", addr_add},
	{"addr_remove", addr_remove},
	{"tunnel_probe_and_rename", tunnel_probe_and_rename},
	{"tunnel_create", tunnel_create},
	{"tunnel_delete", tunnel_delete},
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

	// A SOCK_DGRAM so we can do tunnel stuff..
	dgram_fd = socket(AF_INET, SOCK_DGRAM, 0);
	if(dgram_fd < 0) { 
		fprintf(stderr, "unable to create dgram socket\n"); 
		return 0; 
	}

	// Populate the service descriptor...
	u_svc.fd = nl_cache_fd;
	u_svc.read_func = netlink_read;
	u_svc.write_func = NULL;
	u_svc.need_write_func = NULL;

	// And register...
	fprintf(stderr, "b4reg\n");
	register_service(L, &u_svc);
	fprintf(stderr, "afreg\n");
	return 1;
}

