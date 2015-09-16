#!/bin/bash
#
#------------------------------------------------------------------------------
#
# Starts the qemu emulator with the compiled buildroot for testing new opentik
# configurations.
#
# echo gid gid > /proc/sys/net/ipv4/ping_group_range
#
#------------------------------------------------------------------------------

BUILDROOT=./buildroot
QEMU=./support/bin/qemu
QEMU_OPTIONS="-vga none -nographic -parallel none"
KERNEL=${BUILDROOT}/output/images/vmlinux
KERNEL=${BUILDROOT}/output/images/bzImage
ROOTFS=${BUILDROOT}/output/images/rootfs.ext2
LINUX_ARGS="root=/dev/sda console=ttyS0 pci=realloc"
RNG_ARGS="-object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0"
BASE_NET="-netdev user,id=main,host=10.1.0.1,net=10.1.0.0/24,dhcpstart=10.1.0.16,hostfwd=tcp::8022-10.1.0.16:22 -device e1000,netdev=main"
#EXTRA_NET="-device pcnet"
#BASE_NET="-netdev socket,id=lan,listen=localhost:10234 -device e1000,netdev=lan"
NO_CLOCK="-rtc base=1970-01-01T12:00:00,clock=vm"
FS="-fsdev local,id=opentik,security_model=none,path=./lua -device virtio-9p-pci,fsdev=opentik,mount_tag=opentik"
TAP_NET="-netdev tap,ifname=tap0,script=no,downscript=no,id=tap -device e1000,netdev=tap"
OTHER_NET="-netdev socket,id=mynet0,listen=:1239 -device e1000,netdev=mynet0 \
		-netdev socket,id=mynet1,connect=:1239 -device e1000,netdev=mynet1"
CONSOLE_ARGS=""


${QEMU} ${QEMU_OPTIONS} \
	-kernel ${KERNEL} \
	-drive file=${ROOTFS} \
	-append "${LINUX_ARGS}" \
	${CONSOLE_ARGS} \
	${RNG_ARGS} \
	${BASE_NET} \
	${FS} \
	${NO_CLOCK} \
	${TAP_NET} \
	${OTHER_NET}

#qemu-system-mips -nographic -kernel output/images/vmlinux -drive file=output/images/rootfs.ext2 -append "root=/dev/hda console=ttyS0" -netdev user,id=fred -device pcnet,netdev=fred
