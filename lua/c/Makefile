
#LDFLAGS=-lnl-3 -lnl-route-3
#CFLAGS=-I/usr/include/libnl3 -I/home/essele/dev/tektik/sw/lua-5.3.1/src

CFLAGS=-I../../support/lua-5.3.1/src

OBJS=terminfo.o
LIB=term.so

DEPS=

$(LIB): $(OBJS)
	gcc -shared -o $(LIB) $(OBJS) $(LDFLAGS)

%.o: %.c $(DEPS)
	gcc $(CFLAGS) -c -Wall -Werror -fpic -o $@ $< 

clean:
	rm $(LIB) $(OBJS)

