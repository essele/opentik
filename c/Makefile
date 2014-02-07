
MOSDIR_I="/home/essele/dev/mosquitto/mosquitto-1.2.3/lib"
MOSDIR_L="/home/essele/dev/mosquitto/mosquitto-1.2.3/lib"

LDFLAGS=-L$(MOSDIR_L) -lmosquitto -lpthread -lrt
CFLAGS=-I$(MOSDIR_I)

OBJS=unit.o serialize.o filewatch.o
LIB=unit.so

DEPS=serialize.h filewatch.h luafuncs.h



$(LIB):	$(OBJS)
	gcc -shared -o $(LIB) $(OBJS) $(LDFLAGS)

%.o:	%.c $(DEPS)
	gcc -c -Wall -Werror -fpic -o $@ $< $(CFLAGS)

clean:
	rm $(LIB) $(OBJS)

