#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <poll.h>
#include <curses.h>
#include <term.h>
#include <sys/ioctl.h>

char	PC;			// for tputs
char	*BC;		// for tgoto
char	*UP;

struct termios	old_termio, new_termio;



void int_handler(int sig) {
	printf("CLEANUP");
	ioctl(0, TCSETS, &old_termio);
	exit(1);
}




int outfun(int c) {
	printf("%c", c);
}

struct key {
	char	*ti_name;
	char	*ti_data;
	int		rc;
};

#define XKEY_UP				1024
#define XKEY_DOWN			1025
#define XKEY_LEFT			1026
#define XKEY_RIGHT			1027

struct key	keys[] = {
		// The terminfo database is wrong for cursors??
		{ .ti_name = "--", .ti_data = "\033[A", .rc = XKEY_UP },
		{ .ti_name = "--", .ti_data = "\033[B", .rc = XKEY_DOWN },
		{ .ti_name = "--", .ti_data = "\033[D", .rc = XKEY_LEFT },
		{ .ti_name = "--", .ti_data = "\033[C", .rc = XKEY_RIGHT },

		// Get them anyway...
		{ .ti_name = "ku", .rc = XKEY_UP },
		{ .ti_name = "kd", .rc = XKEY_DOWN },
		{ .ti_name = "kl", .rc = XKEY_LEFT },
		{ .ti_name = "kr", .rc = XKEY_RIGHT },

		// End the list...
		{ .ti_name = NULL }
};

/*
 * Initialise teh keys structures to include the terminfo
 * strings
 */
void init_keys() {
	int i=0;
	while(keys[i].ti_name) {
		if(keys[i].ti_name[0] != '-') {
			keys[i].ti_data = tgetstr(keys[i].ti_name, NULL);
		}
		i++;
	}
}


/*
 * Wait for up to ms milliseconds for a character and return it
 * (return 0 if no char), reduce ms by elapsed time
 */
char	get_char(int *ms) {
	struct timespec before, after, timeout;
	struct pollfd	fds[1];
	int				rc;
	char			c;

	timeout.tv_sec = 0;
	timeout.tv_nsec = *ms * 1000 * 1000;

	fds[0].fd = 0;
	fds[0].events = POLLIN;
	fds[0].revents = 0;

	clock_gettime(CLOCK_MONOTONIC, &before);
	rc = ppoll(fds, 1, &timeout, NULL);

	if(rc == 0) {
		// we have nothing!
		*ms = 0;
		return 0;
	}

	clock_gettime(CLOCK_MONOTONIC, &after);
	*ms -= ((after.tv_sec - before.tv_sec)*1000) + 
								((after.tv_nsec - before.tv_nsec)/1000000);
	if(*ms < 0) *ms = 0;

	rc = read(0, &c, 1);
	return c;
}


/*
 * Read a character and return it.
 * If the string so far is a partial match for one of our special
 * strings then wait to see if we get more characters.
 */
char	read_key() {
	static char	buffer[5];
	static int	bsize = 0, bpos = 0;

	// If we have nothing buffered, then we need to read...
	if(!bsize) {
		int ms = 0;
		while(1) {
			char c = get_char(&ms);
			if(c == 0) {
				if(bsize == 0) {
					ms = 0; 
					continue;		// loop until we get something
				}
				break;
			}
			buffer[bsize++] = c;

			// Optimisation since we know all the codes start with ESC
			if(buffer[0] != 27) break;

			// See if we have a full or partial match...
			int i = 0, partial = 0;
			while(keys[i].ti_name) {
				int klen = strlen(keys[i].ti_data);
				int j;
				if(strncmp(buffer, keys[i].ti_data, bsize) == 0) {
					if(klen == bsize) {
						fprintf(stderr, "got match on i=%d v=%d\n", i, keys[i].rc);
						bsize = bpos = 0;
						return 0;
					}
					partial = 1;
					if(bsize == 1) ms = 900;
				}
				i++;
			}
			if(partial) continue;
			break;
		}
	}

	// If we have something in the buffer then we return it
	if(bsize) {
		char c = buffer[bpos];
		bsize--; bpos++;
		if(bsize == 0) { bpos = 0; }
		return c;
	}
	fprintf(stderr, "aaarrgg\n");
}


int main() {

	int		rc;
	char	*temp;
	char	*termtype = getenv("TERM");

	if(!termtype) {
		fprintf(stderr, "no TERM defined!\n");
		exit(1);
	}

	ioctl(0, TCGETS, &old_termio);
	new_termio = old_termio;
	new_termio.c_lflag &= ~ECHO;
	new_termio.c_lflag &= ~ICANON;

	ioctl(0, TCSETS, &new_termio);
	

	signal(SIGQUIT, int_handler);
	signal(SIGINT, int_handler);
	
	rc = tgetent(NULL, termtype);
	fprintf(stderr, "rc=%d\n", rc);

	int height = tgetnum("li");
	int width = tgetnum("co");
	printf("w=%d h=%d\n", height, width);

	temp = tgetstr("pc", NULL);
	PC = temp ? *temp : 0;
	BC = tgetstr("le", NULL);
	UP = tgetstr("up", NULL);


	char *keyu = tgetstr("ku", NULL);
	int xx = strlen(keyu);
	int i;
	for(i=0; i < xx; i++) {
		printf("%d: [%d]\n", i, keyu[i]);
	}
	tputs(tgetstr("ke", NULL), 1, outfun);

	init_keys();

	char c;
	int xp = 0;

	while(1) {
//		read(0, &c, 1);
		c = read_key();

		if(c == 27) {
			printf("X");
		} else if(c == 127) {
			// if we are the first char of the screen then we need to backup to the
			// end of the previous line
			//
			if(xp == 0) {
				//printf("-");
				tputs(tgetstr("up", NULL), 1, outfun);
				int i;
				for(i=0; i < width; i++) {
					tputs(tgetstr("nd", NULL), 1, outfun);
				}
				outfun(' ');
				xp = width-1;
			} else {
				tputs(BC, 1, outfun);
				outfun(' ');
				tputs(BC, 1, outfun);
				xp--;
			}
		} else if(c == '\000') {
			tputs(tgetstr("up", NULL), 1, outfun);
		} else {
			printf("%c", c);
			xp++;
			if(xp == width) { 
				xp = 0; 
				tputs(tgetstr("cr", NULL), 1, outfun);
				tputs(tgetstr("do", NULL), 1, outfun);
			}

			// if we are the last char of the term, then we need to move to the next
			// line (if we don't autowrap)
		}
		fflush(stdout);
	}

	tputs(tgoto(tgetstr("cm", NULL), 5, 5), 1, outfun);
	printf("X");
	return 0;
}
