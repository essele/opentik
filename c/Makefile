
MOSDIR_I="/home/essele/dev/opentik/mosquitto-1.2.3/lib"
MOSDIR_L="/home/essele/dev/opentik/mosquitto-1.2.3/lib"
LUADIR_I="/home/essele/dev/opentik/luajit-2.0/src"

LDFLAGS=-L$(MOSDIR_L) -lmosquitto -lpthread -lrt -lnl-3 -lnl-route-3
CFLAGS=-I$(MOSDIR_I) -I$(LUADIR_I) -I/usr/include/libnl3

OBJS=unit.o serialize.o filewatch.o netlink.o
LIB=unit.so

DEPS=serialize.h filewatch.h luafuncs.h



$(LIB):	$(OBJS)
	gcc -shared -o $(LIB) $(OBJS) $(LDFLAGS)

%.o:	%.c $(DEPS)
	gcc -c -Wall -Werror -fpic -o $@ $< $(CFLAGS)

clean:
	rm $(LIB) $(OBJS)

