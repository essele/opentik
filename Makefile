

EXTERNAL=br-opentik
BRDIR=buildroot

all:
	make -C $(BRDIR) BR2_EXTERNAL=../$(EXTERNAL)

#
# Build lua from the support tree and link the binary into the support/bin
# directory
#
lua:	support/bin/lua support/lib/posix.so

support/bin/lua:
	make -C support/lua-5.3.1 linux && ln -s ../lua-5.3.1/src/lua support/bin/lua

export LUA = $(shell pwd)/support/bin/lua
export LUA_INCLUDE = -I$(shell pwd)/support/lua-5.3.1/src

support/lib/posix.so: support/bin/lua
	(cd support/luaposix-release-v33.3.1 && ./configure && make) \
		&& ln -s ../luaposix-release-v33.3.1/ext/posix/.libs/posix.so support/lib/posix.so

#
# QEMU
#

qemu:	support/bin/qemu

support/bin/qemu:
	(cd support/qemu-2.2.0 && ./configure --target-list=x86_64-softmmu --enable-virtfs \
		&& make) && ln -s ../qemu-2.2.0/x86_64-softmmu/qemu-system-x86_64 support/bin/qemu

menuconfig:
	make -C $(BRDIR) BR2_EXTERNAL=../$(EXTERNAL) menuconfig

linux-menuconfig:
	make -C $(BRDIR) BR2_EXTERNAL=../$(EXTERNAL) linux-menuconfig

	

