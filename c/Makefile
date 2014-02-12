
MOSDIR_I="/home/essele/dev/opentik/mosquitto-1.2.3/lib"
MOSDIR_L="/home/essele/dev/opentik/mosquitto-1.2.3/lib"
LUADIR_I="/home/essele/dev/opentik/luajit-2.0/src"

LDFLAGS=-L$(MOSDIR_L) -lmosquitto -lpthread -lrt -lnl-3 -lnl-route-3
CFLAGS=-I$(MOSDIR_I) -I$(LUADIR_I) -I/usr/include/libnl3

DEPS=serialize.h filewatch.h luafuncs.h netlink.h tunnel.h unit_service.h

UNITOBJS=unit.o unit_service.o serialize.o tunnel.o
UNITLIB=unit.so

NLOBJS=netlink.o
NLLIB=netlink.so

TUNNELOBJS=tunnel.o
TUNNELLIB=tunnel.so

FWOBJS=filewatch.o
FWLIB=filewatch.so

LIBS=$(UNITLIB) $(NLLIB) $(TUNNELLIB) $(FWLIB)

all:	$(LIBS)

$(UNITLIB):	$(UNITOBJS)
	gcc -shared -o $(UNITLIB) $(UNITOBJS) $(LDFLAGS)

$(NLLIB):	$(NLOBJS)
	gcc -shared -o $(NLLIB) $(NLOBJS) $(LDFLAGS)

$(FWLIB):	$(FWOBJS)
	gcc -shared -o $(FWLIB) $(FWOBJS) $(LDFLAGS)

$(TUNNELLIB):	$(TUNNELOBJS)
	gcc -shared -o $(TUNNELLIB) $(TUNNELOBJS) $(LDFLAGS)

%.o:	%.c $(DEPS)
	gcc -c -Wall -Werror -fpic -o $@ $< $(CFLAGS)

clean:
	rm $(UNITLIB) $(UNITOBJS) $(TUNNELLIB) $(TUNNELOBJS)

