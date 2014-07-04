#include <stdio.h>
#include <stdlib.h>
#include <ncurses.h>
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

int main(int argc, char *argv[]) {
	int x;

	initscr();
	if(has_colors() == FALSE) {
		endwin();
		printf("no color\n");
		exit(1);
	}
	start_color();
	use_default_colors();

	init_pair(0, COLOR_BLACK, -1);
	init_pair(1, COLOR_RED, -1);
	init_pair(2, COLOR_GREEN, -1);
	init_pair(3, COLOR_YELLOW, -1);
	init_pair(4, COLOR_BLUE, -1);
	init_pair(5, COLOR_MAGENTA, -1);
	init_pair(6, COLOR_CYAN, -1);
	init_pair(7, COLOR_WHITE, -1);

	scrollok(stdscr, TRUE);
	cbreak(); noecho();
	refresh();

	int mx, my;

	getmaxyx(stdscr, my, mx);
/*
	endwin();
	printf("mx=%d my=%d\n", mx, my);
	exit(1);
*/
	mx--;
	move(my-1, 2);	

	refresh();

	sleep(2);

	printw("hello");

	refresh();
	sleep(2);

	for(x=0; x < 200; x++) {
//		char	buf[128];

		if(stdscr->_flags & _WRAPPED) {
			printw("X");
		} else {
			printw("-");
		}
/*
		sprintf(buf, "Line: %d\n", x);
		attron(COLOR_PAIR((x%8)));
		printw(buf);
		attroff(COLOR_PAIR((x%8)));
*/
		refresh();
		usleep(100*1000);
	}
	endwin();
	
	return 0;
}

/*==============================================================================
 * These are the functions we export to Lua...
 *==============================================================================
 */
static const struct luaL_reg lib[] = {
//	{"service_loop", service_loop},
//	{"serialize", do_serialize},
//	{"unserialize", do_unserialize},
	{NULL, NULL}
};

/*------------------------------------------------------------------------------
 * Main Library Entry Point ... we initialise all of our lua functions, then
 * we work out what our module name is and setup mosquitto and the service
 * handler
 *------------------------------------------------------------------------------
 */
int luaopen_unit(lua_State *L) {
	// Initialise the library...
	luaL_openlib(L, "unit", lib, 0);
	return 1;
}

