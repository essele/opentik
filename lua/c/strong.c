#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/un.h>


// socket(PF_FILE, SOCK_STREAM, 0)         = 7
// connect(7, {sa_family=AF_FILE, path="/var/run/charon.vici"}, 22) = 0
// write(4, "u", 1)                        = 1
// futex(0x1292cb4, FUTEX_WAKE_OP_PRIVATE, 1, 1, 0x1292cb0, {FUTEX_OP_SET, 0, FUTEX_OP_CMP_GT, 1}) = 1
// futex(0x1292c48, FUTEX_WAKE_PRIVATE, 1) = 1
// sendto(7, "\0\0\0\v", 4, 0, NULL, 0)    = 4
// sendto(7, "\3", 1, 0, NULL, 0)          = 1
// sendto(7, "\t", 1, 0, NULL, 0)          = 1
// sendto(7, "list-conn", 9, 0, NULL, 0)   = 9
// futex(0x12be474, FUTEX_WAIT_PRIVATE, 1, NULL) = 0
// futex(0x12c1828, FUTEX_WAKE_PRIVATE, 1) = 0
// write(4, "u", 1)                        = 1
// futex(0x1292cb4, FUTEX_WAKE_OP_PRIVATE, 1, 1, 0x1292cb0, {FUTEX_OP_SET, 0, FUTEX_OP_CMP_GT, 1}) = 1
// futex(0x1292c48, FUTEX_WAKE_PRIVATE, 1) = 1
// sendto(7, "\0\0\0\f", 4, 0, NULL, 0)    = 4
// sendto(7, "\0", 1, 0, NULL, 0)          = 1
// sendto(7, "\n", 1, 0, NULL, 0)          = 1
// sendto(7, "list-conns", 10, 0, NULL, 0) = 10
// futex(0x12be474, FUTEX_WAIT_PRIVATE, 3, NULLad-secure: IKEv1/2
//   local:  5.133.182.9
//   remote: %any
//   local pre-shared key authentication:
//     id: 5.133.182.9
//   remote pre-shared key authentication:
//   ad-secure: TUNNEL
//     local:  0.0.0.0/0
//     remote: 192.168.95.0/24
// ) = 0
// futex(0x12c1828, FUTEX_WAKE_PRIVATE, 1) = 0
// write(4, "u", 1)                        = 1
// futex(0x1292cb4, FUTEX_WAKE_OP_PRIVATE, 1, 1, 0x1292cb0, {FUTEX_OP_SET, 0, FUTEX_OP_CMP_GT, 1}) = 1
// futex(0x1292c48, FUTEX_WAKE_PRIVATE, 1) = 1
// futex(0x12934a8, FUTEX_WAKE_PRIVATE, 1) = 1
// write(4, "u", 1)                        = 1
// futex(0x12934a8, FUTEX_WAKE_PRIVATE, 1) = 1
// close(7)                                = 0
// tgkill(29573, 29574, SIGRTMIN)          = 0
// 

int main(int argc, char *argv[]) {

	int 				s;
	int					rc;
	struct sockaddr_un 	dest;
	char				*path = "/var/run/charon.vici";
	size_t				size = sizeof(sa_family_t) + strlen(path) + 1;

	dest.sun_family = AF_UNIX;
	strcpy(dest.sun_path, path);
	

	s = socket(AF_FILE, SOCK_STREAM, 0);
	printf("s=%d\n", s);

	rc = connect(s, (struct sockaddr *)&dest, size);
	printf("rc=%d\n", rc);
	

	exit(0);
}
