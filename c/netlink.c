#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <netlink/netlink.h>
#include <netlink/cache.h>
#include <netlink/route/link.h>



int main(int argc, char *argv[]) {

	struct nl_handle	*nls;

	nls = nl_handle_alloc();
	

	nl_connect(nls, NETLINK_ROUTE);

	return 0;
}
