
LIBS=tunnel.so fred.so

DEPS_tunnel=hello

$(LIBS) : %.so : %.o
	$(CC) -o $@ $< -I $(DEPS_$*)/fred $(CFLAGS)

all: $(LIBS)
