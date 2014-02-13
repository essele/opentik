
MOSDIR_I="/home/essele/dev/opentik/mosquitto-1.2.3/lib"
MOSDIR_L="/home/essele/dev/opentik/mosquitto-1.2.3/lib"
LUADIR				= /home/essele/dev/opentik/luajit-2.0/src

CFLAGS				= -I$(LUADIR)
LDFLAGS				= -L$(LUADIR)

#
# Special per-file C and LD FLAGS
#
CFLAGS_mosquitto.o		= -I$(MOSDIR_I) 
LDFLAGS_mosquitto.so 	= -L$(MOSDIR_L) -lmosquitto -lpthread -lrt

CFLAGS_netlink.o		= -I/usr/include/libnl3
LDFLAGS_netlink.so		= -lnl-3 -lnl-route-3


%.so:	%.o
	$(CC) -shared -o $@ $(CFLAGS) $(CFLAGS_$@) $(LDFLAGS) $(LDFLAGS_$@) $^

%.o:	%.c %.d
	$(CC) -c -Wall -Werror -fpic -o $@ $(CFLAGS) $(CFLAGS_$@) $<

%.d:	%.c
	$(CC) -MM $*.c > $@

#
# All of the LIBS we wan to build
#
LIBS				= netlink.so mosquitto.so filewatch.so unit.so tunnel.so

all:				$(LIBS)
clean:
	rm *.o *.so

#
# If a lib has more than one object...
#
mosquitto.so:		mosquitto.o serialize.o



