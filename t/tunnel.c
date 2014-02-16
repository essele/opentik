#include <stdio.h>
#include <string.h>
#include <stdlib.h>
//#include <lua.h>
//#include <lauxlib.h>
//#include <lualib.h>
#include <arpa/inet.h>
#include <netlink/netlink.h>
#include <netlink/cache.h>
#include <netlink/route/rtnl.h>
#include <netlink/route/link.h>
#include <netlink/route/addr.h>

#include <netinet/ip.h>
//#include <net/if.h>
#include <net/if_arp.h>

#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>




#include <linux/sockios.h>
#include <linux/if_tunnel.h>


int main(int argc, char *argv[]) {

	int						fd;
	int						rc;
	struct ip_tunnel_parm	tp;
	struct ip_tunnel_parm	*p = &tp;
	struct ifreq			ifr;

	fprintf(stderr, "hello");

	strcpy(ifr.ifr_name, "__gre");
	ifr.ifr_ifru.ifru_data = (void *)p;

	fd = socket(AF_INET, SOCK_DGRAM, 0);
	fprintf(stderr, "fd=%d\n", fd);

	memset(p, 0, sizeof(struct ip_tunnel_parm));

	p->iph.version = 4;
	p->iph.ihl = 5;
	p->iph.frag_off = htons(IP_DF);
	
	p->iph.daddr = inet_addr("10.4.4.1");
	p->iph.saddr = inet_addr("10.4.5.1");
	
	strcpy(p->name, "greYY");

	p->iph.protocol = IPPROTO_GRE;

	fprintf(stderr, "name=%s\n", p->name);
	rc = ioctl(fd, SIOCADDTUNNEL, &ifr);
	fprintf(stderr, "set ioctl=%d\n", rc);

	close(fd);
	exit(0);

}

