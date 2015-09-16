

EXTERNAL=br-opentik
BRDIR=buildroot

all:
	make -C$(BRDIR) BR2_EXTERNAL=../$(EXTERNAL)

menuconfig:
	make -C$(BRDIR) BR2_EXTERNAL=../$(EXTERNAL) menuconfig

linux-menuconfig:
	make -C$(BRDIR) BR2_EXTERNAL=../$(EXTERNAL) linux-menuconfig

	

