

EXTERNAL=br-opentik
BRDIR=buildroot

menuconfig:
	make -C$(BRDIR) BR2_EXTERNAL=../$(EXTERNAL) menuconfig

linux-menuconfig:
	make -C$(BRDIR) BR2_EXTERNAL=../$(EXTERNAL) linux-menuconfig

all:
	make -C$(BRDIR) BR2_EXTERNAL=../$(EXTERNAL)
	

