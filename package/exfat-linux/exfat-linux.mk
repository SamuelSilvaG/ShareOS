#############################################################
#
# exfat-linux
#
#############################################################

# not needed as a package, a kernel patch is applied to build the module in kernel.

#!/bin/sh
#
# # HOW to build out of tree, for Alt-F-1.0, kernel 4.4.86
#
# # EXFAT_LINUX_VERSION := 2.2.0-3arter97 # for pre 4.9 kernels
# # needs a linux-4.4.86 kernel source configured for the given box
# KDIR=/Alt-F/alt-f-sf/linux-4.4.86
# cd $KDIR
# cp ../local/<box>/linux-4.4.86.config .config
# # and build, with the buildroot cross-toolchain in the PATH
# export PATH=/usr/bin:/bin:/Alt-F/alt-f-sf/build/build_arm/host_dir/usr/bin
# ARCH=arm CROSS_COMPILE=arm-linux- make -j 4 V=1 >& po.log
# cd to the exfat-linux and build the module 
# KVER=4.4.86
# BARCH=armv5  # replace armv5 with armv7 for DNS-327
# ARCH=arm CROSS_COMPILE=arm-linux- KDIR=$KDIR make V=1 $1
# if test -n "$1"; then exit; fi
# 
# and the package
# mkdir -p tmp/CONTROL
# cp exfat-linux-$BARCH.control tmp/CONTROL/control
# cp exfat-linux.postinst tmp/CONTROL/postinst
# next is not working as expected, at target pkg install it creates a fake link
# ln -sfr tmp/CONTROL/postinst tmp/CONTROL/postrm
# 
# mkdir -p tmp/usr/lib/modules/$KVER/kernel/fs/exfat/
# cp exfat.ko tmp/usr/lib/modules/$KVER/kernel/fs/exfat/
# 
# ipkg-build -o root -g root tmp

EXFAT_LINUX_VERSION := 5.8-1arter97
EXFAT_LINUX_SOURCE = exfat-linux-$(EXFAT_LINUX_VERSION).tar.gz
EXFAT_LINUX_SOURCE2 = $(EXFAT_LINUX_VERSION).tar.gz
EXFAT_LINUX_SITE = https://github.com/arter97/exfat-linux/archive/refs/tags
EXFAT_LINUX_WGET_OPTS = -O $(DL_DIR)/exfat-linux-$(EXFAT_LINUX_VERSION).tar.gz

EXFAT_LINUX_AUTORECONF = NO
EXFAT_LINUX_DEPENDENCIES = linux26-modules

$(eval $(call AUTOTARGETS,package,exfat-linux))

quote:="
LINVER=$(subst $(quote),$(empty),$(BR2_CUSTOM_LINUX26_VERSION))
M_DIR=$(TARGET_DIR)/usr/lib/modules/$(LINVER)/kernel/fs/exfat

$(EXFAT_LINUX_TARGET_SOURCE):
	$(call DOWNLOAD,$(EXFAT_LINUX_SITE),$(EXFAT_LINUX_SOURCE2), $(EXFAT_LINUX_WGET_OPTS))
	mkdir -p $(BUILD_DIR)/exfat-linux-$(EXFAT_LINUX_VERSION)
	touch $@

$(EXFAT_LINUX_TARGET_CONFIGURE):
	touch $@

$(EXFAT_LINUX_TARGET_BUILD):
	$(LINUX26_MAKE_FLAGS) KDIR=$(LINUX_DIR) $(MAKE) -C $(EXFAT_LINUX_DIR)
	touch $@

$(EXFAT_LINUX_TARGET_INSTALL_TARGET):
	mkdir -p $(M_DIR)
	cp $(EXFAT_LINUX_DIR)/exfat.ko $(M_DIR)
	$(STAGING_DIR)/bin/$(GNU_TARGET_NAME)-depmod26 -b $(TARGET_DIR) $(LINVER)
	touch $@

$(EXFAT_LINUX_TARGET_UNINSTALL):
	rm -rf $(M_DIR)
	$(STAGING_DIR)/bin/$(GNU_TARGET_NAME)-depmod26 -b $(TARGET_DIR) $(LINVER)
	touch $@

$(EXFAT_LINUX_TARGET_CLEAN):
	$(LINUX26_MAKE_FLAGS) KDIR=$(LINUX_DIR) $(MAKE) -C $(EXFAT_LINUX_DIR) clean
	$(RM) $(EXFAT_LINUX_DIR)/{.stamp_built,.stamp_cleaned}
	touch $@
