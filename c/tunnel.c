
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <netinet/ip.h>
#include <net/if.h>
#include <net/if_arp.h>

#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <linux/sockios.h>
#include <linux/if_tunnel.h>

#include "unit_service.h"

struct		unit_service_desc	us;

static int my_read(lua_State *L, int fd) {
	fprintf(stderr, "in my_read\n");	
	return 0;
}


static int get_service(lua_State *L) {
	us.fd = 5;
	us.read_func = my_read;
	
	lua_pushlightuserdata(L, (void *)&us);
	return 1;
}



int tun_test() {
	int						fd;
	int						rc;
	struct ip_tunnel_parm	tp;
	struct ip_tunnel_parm	*p = &tp;
	struct ifreq			ifr;

	fprintf(stderr, "hello");

	strcpy(ifr.ifr_name, "gre0");
	ifr.ifr_ifru.ifru_data = (void *)p;

	fd = socket(AF_INET, SOCK_DGRAM, 0);
	fprintf(stderr, "fd=%d\n", fd);


	memset(p, 0, sizeof(struct ip_tunnel_parm));

	rc = ioctl(fd, SIOCGETTUNNEL, &ifr);
	fprintf(stderr, "ioctl=%d\n", rc);

/*	
	p->iph.version = 4;
	p->iph.ihl = 5;
	p->iph.frag_off = htons(IP_DF);
	
	p->iph.daddr = inet_addr("10.4.4.1");
	p->iph.saddr = inet_addr("10.4.5.1");
	
	strcpy(p->name, "greYY");

	p->iph.protocol = IPPROTO_GRE;



	
	rc = ioctl(fd, SIOCADDTUNNEL, &ifr);
	fprintf(stderr, "ioctl=%d\n", rc);
*/
	close(fd);
	return 0;
}


static int tt(lua_State *L) {
	tun_test();
	return 0;
}

/*==============================================================================
 *  * These are the functions we export to Lua...
 *   *==============================================================================
 *	*/
static const struct luaL_reg lib[] = {
	{"tt", tt},
	{"get_service", get_service},
	{NULL, NULL}
};

/*------------------------------------------------------------------------------
 *  * Main Library Entry Point ... just intialise all the functions
 *   *------------------------------------------------------------------------------
 *	*/
int luaopen_tunnel(lua_State *L) {
	luaL_openlib(L, "tunnel", lib, 0);
	return 1;
}




