
LDFLAGS=-lnl-3 -lnl-route-3
CFLAGS=-I/usr/include/libnl3 -I/home/essele/dev/tektik/sw/lua-5.3.1/src

ALL: lee.so strong

OBJS=nl.o
LIB=lee.so

DEPS=

$(LIB): $(OBJS)
	gcc -shared -o $(LIB) $(OBJS) $(LDFLAGS)

%.o: %.c $(DEPS)
	gcc $(CFLAGS) -c -Wall -Werror -fpic -o $@ $< 

fred: fred.c
	gcc -o fred fred.c

clean:
	rm $(LIB) $(OBJS)

