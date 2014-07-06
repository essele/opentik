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

/*
 * Table for reading termcap keys
 */
struct {
	char	*name;
	char	*data;
	int		len;
	int		rc;
} ti_keys[] = {
		// The terminfo database is wrong for cursors??
		{ "ku", "\033[A", 3, KEY_UP },
		{ "kd", "\033[B", 3, KEY_DOWN },
		{ "kl", "\033[D", 3, KEY_LEFT },
		{ "kr", "\033[C", 3, KEY_RIGHT },

		// Get them defined ones anyway...
		{ "ku", NULL, 0, KEY_UP },
		{ "kd", NULL, 0, KEY_DOWN },
		{ "kl", NULL, 0, KEY_LEFT },
		{ "kr", NULL, 0, KEY_RIGHT },

		// End the list...
		{ NULL, NULL, 0 }
};

static int shortest_key_data = 999;
static int longest_key_data = 0;

char	*nd, *up;

/*
 * Table for reading termcap strings
 */
struct {
	char	*name;
	char	**ptr;
} ti_strings[] = {
		{ "nd", &nd },
		{ "up", &up },
		{ NULL, NULL }
};

int		am, xn;

/*
 * Table for reading termcap flags
 */
struct {
	char	*name;
	int		*ptr;
} ti_flags[] = {
		{ "am", &am },
		{ "xn", &xn },
		{ NULL, NULL }
};



/*
 * Initialise the termcap/terminfo strings
 */
void init_terminfo_data(char **buf) {
	int i, len;

	// First the strings...
	for(i=0; ti_strings[i].name; i++) {
		char	*s = tgetstr(ti_strings[i].name, buf);
		if(!s) {
			fprintf(stderr, "missing termcap capability [%s]\n", ti_strings[i].name);
		} else {
			*ti_strings[i].ptr = s;
		}
	}

	// Now the keys...	
	for(i=0; ti_keys[i].name; i++) {
		if(!ti_keys[i].data) {
			char *p = tgetstr(ti_keys[i].name, buf);
			if(p) {
				len = strlen(p);
				ti_keys[i].len = len;
				ti_keys[i].data = p;
				if(len < shortest_key_data) shortest_key_data = len;
				if(len > longest_key_data) longest_key_data = len;
			}
		}
	}

	// Now the flags...
	for(i=0; ti_flags[i].name; i++) {
		*ti_flags[i].ptr = tgetflag(ti_flags[i].name);
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
int	read_key() {
	static char *buffer = NULL;
	static int	bsize = 0, bpos = 0;
	int			i;

	if(!buffer) buffer = malloc(longest_key_data + 1);

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
			int partial = 0;
			for(i=0; ti_keys[i].name; i++) {
				if(!ti_keys[i].data) continue;

				int klen = ti_keys[i].len;
				if(strncmp(buffer, ti_keys[i].data, bsize) == 0) {
					if(klen == bsize) {
						bsize = bpos = 0;
						return ti_keys[i].rc;
					}
					partial = 1;
					if(bsize == 1) ms = 900;

					// if we are shorter than the shortest key data
					// then no need to keep looking...
					if(bsize < shortest_key_data) break;
				}
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
	printf("w=%d h=%d\n", width, height);

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
//	tputs(tgetstr("ke", NULL), 1, outfun);

	int am = tgetflag("am");
	int xn = tgetflag("xn");
	int LP = tgetflag("LP");

	fprintf(stderr, "am=%d xn=%d LP=%d\n", am, xn, LP);

	char	*buf = malloc(2048);
	char	*obuf = buf;

	init_terminfo_data(&buf);

	int c;
	int xp = 0;

	while(1) {
		c = read_key();

		switch(c) {

		case KEY_LEFT:
			tputs(BC, 1, outfun);
			xp--;
			break;

		case KEY_RIGHT:
			tputs(tgetstr("nd", NULL), 1, outfun);
			xp++;
			break;

		case 27:
			printf("X");
			break;

		case 127:
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
				outfun('\n');
				tputs(tgetstr("up", NULL), 1, outfun);
				for(i=0; i < width; i++) {
					tputs(tgetstr("nd", NULL), 1, outfun);
				}


				xp = width-1;
			} else {
				tputs(BC, 1, outfun);
				outfun(' ');
				tputs(BC, 1, outfun);
				xp--;
			}
			break;

		default:
			printf("%c", c);
			xp++;
			if(xp == width) { 
				xp = 0; 
//				tputs(tgetstr("cr", NULL), 1, outfun);
//				tputs(tgetstr("do", NULL), 1, outfun);
				printf("\n");
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
