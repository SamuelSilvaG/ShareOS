#############################################################
#
# e2fsprogs
#
#############################################################

#E2FSPROGS_VERSION:=1.41.14
##E2FSPROGS_VERSION:=1.42.13
#E2FSPROGS_VERSION:=1.43.3 rootfs too big by 131136/53312 bytes (Alt-F-1.1)
#E2FSPROGS_VERSION:=1.44.2 rootfs too big by 69696/36928 bytes (Alt-F-1.1)
# pkg is 149KB bigger, extra is 96KB bigger, exfat patches not needed
E2FSPROGS_VERSION:=1.47.1

E2FSPROGS_SOURCE=e2fsprogs-$(E2FSPROGS_VERSION).tar.gz
E2FSPROGS_SITE=$(BR2_SOURCEFORGE_MIRROR)/project/e2fsprogs/e2fsprogs/v$(E2FSPROGS_VERSION)

# E2FSPROGS_DIR=$(BUILD_DIR)/e2fsprogs-$(E2FSPROGS_VERSION)
# E2FSPROGS_CAT:=$(ZCAT)
# E2FSPROGS_BINARY:=misc/mke2fs
# E2FSPROGS_TARGET_BINARY:=usr/sbin/mke2fs

E2FSPROGS_MAKE = $(MAKE1)
E2FSPROGS_LIBTOOL_PATCH := NO
E2FSPROGS_INSTALL_STAGING = YES

E2FSPROGS_CONF_ENV = CFLAGS="$(TARGET_CFLAGS) $(BR2_PACKAGE_E2FSPROGS_OPTIM)"
E2FSPROGS_CONF_OPT = --enable-elf-shlibs --disable-static \
	--enable-symlink-install --enable-relative-symlinks \
	--without-crond-dir \
	--without-systemd-unit-dir --without-udev-rules-dir \
	--disable-testio-debug --disable-jbd-debug  --disable-backtrace \
	--enable-resizer --enable-fsck --disable-tls \
	--disable-e2initrd-helper --enable-defrag \
	--enable-libuuid --enable-libblkid \
	--disable-uuidd --enable-debugfs --enable-imager \
	--disable-nls --without-libarchive --disable-fuse2fs

E2FSPROGS_INSTALL_TARGET_OPT = DESTDIR=$(TARGET_DIR) install
E2FSPROGS_INSTALL_STAGING_OPT = DESTDIR=$(STAGING_DIR) install-libs

E2FSPROGS_HOST_CONF_OPT = $(E2FSPROGS_CONF_OPT)
E2FSPROGS_HOST_INSTALL_OPT = DESTDIR=$(HOST_DIR) install-libs

E2FSPROGS_EXTRA_BIN = ./usr/lib/libss.so ./usr/lib/libss.so.2 \
	./usr/lib/libss.so.2.0 ./usr/sbin/dumpe2fs ./usr/sbin/filefrag \
	./usr/sbin/e2undo ./usr/sbin/e2scrub ./usr/sbin/e2scrub_all \
	./usr/sbin/logsave ./usr/sbin/uuidd ./usr/sbin/debugfs \
	./usr/sbin/e2image ./usr/sbin/e2freefrag ./usr/sbin/findfs \
	./usr/sbin/badblocks ./usr/sbin/e4defrag ./usr/sbin/e4crypt \
	./usr/sbin/e2mmpstatus ./etc/e2scrub.conf ./usr/bin/compile_et \
	./usr/share/et ./usr/share/ss ./usr/bin/mk_cmds

$(eval $(call AUTOTARGETS,package,e2fsprogs))
$(eval $(call AUTOTARGETS_HOST,package,e2fsprogs))

# major()/makedev() "patch" for the host
# $(E2FSPROGS_HOST_HOOK_POST_EXTRACT):
# 	sed -i '/config.h/a #include <sys/sysmacros.h>' $(E2FSPROGS_HOST_DIR)/lib/ext2fs/ismounted.c $(E2FSPROGS_HOST_DIR)/lib/blkid/devname.c
# 	touch $@
	
$(E2FSPROGS_HOOK_POST_INSTALL):
ifneq ($(BR2_PACKAGE_E2FSPROGS_EXTRA),y)
	( cd $(TARGET_DIR); rm -rf $(E2FSPROGS_EXTRA_BIN) )
endif
	touch $@
# several other packages depends on this target
libuuid: e2fsprogs

# $(DL_DIR)/$(E2FSPROGS_SOURCE):
# 	 $(call DOWNLOAD,$(E2FSPROGS_SITE),$(E2FSPROGS_SOURCE))
# 
# e2fsprogs-source: $(DL_DIR)/$(E2FSPROGS_SOURCE)
# 
# $(E2FSPROGS_DIR)/.unpacked: $(DL_DIR)/$(E2FSPROGS_SOURCE)
# 	$(E2FSPROGS_CAT) $(DL_DIR)/$(E2FSPROGS_SOURCE) | tar -C $(BUILD_DIR) $(TAR_OPTIONS) -
# 	toolchain/patch-kernel.sh $(E2FSPROGS_DIR) package/e2fsprogs/ e2fsprogs-$(E2FSPROGS_VERSION)\*.patch
# 	$(CONFIG_UPDATE) $(E2FSPROGS_DIR)/config
# 	touch $@
# 
# $(E2FSPROGS_DIR)/.configured: $(E2FSPROGS_DIR)/.unpacked
# 	(cd $(E2FSPROGS_DIR); rm -rf config.cache; \
# 		$(TARGET_CONFIGURE_OPTS) \
# 		$(TARGET_CONFIGURE_ARGS) \
# 		$(TARGET_CONFIGURE_ENV) \
# 		CFLAGS="$(TARGET_CFLAGS) $(BR2_PACKAGE_E2FSPROGS_OPTIM)" \
# 		./configure \
# 		--target=$(GNU_TARGET_NAME) \
# 		--host=$(GNU_TARGET_NAME) \
# 		--build=$(GNU_HOST_NAME) \
# 		--prefix=/usr \
# 		--exec-prefix=/usr \
# 		--bindir=/usr/bin \
# 		--sbindir=/usr/sbin \
# 		--libdir=/usr/lib \
# 		--libexecdir=/usr/lib \
# 		--sysconfdir=/etc \
# 		--datadir=/usr/share \
# 		--localstatedir=/var \
# 		--mandir=/usr/share/man \
# 		--infodir=/usr/share/info \
# 		$(E2FSPROGS_OPTS) \
# 		$(DISABLE_NLS) \
# 		$(DISABLE_LARGEFILE) \
# 	)
# 	touch $@
# 
# $(E2FSPROGS_DIR)/$(E2FSPROGS_BINARY): $(E2FSPROGS_DIR)/.configured
# 	$(MAKE1) -C $(E2FSPROGS_DIR)
# 	touch -c $@
# 
# $(TARGET_DIR)/$(E2FSPROGS_TARGET_BINARY): $(E2FSPROGS_DIR)/$(E2FSPROGS_BINARY)
# 	$(MAKE1) -C $(E2FSPROGS_DIR) DESTDIR=$(STAGING_DIR) install-libs
# 	$(MAKE1) -C $(E2FSPROGS_DIR) DESTDIR=$(TARGET_DIR) install
# ifneq ($(BR2_PACKAGE_E2FSPROGS_EXTRA),y)
# 	( cd $(TARGET_DIR); rm -f $(E2FSPROGS_EXTRA_BIN) )
# endif
# 	touch -c $@
# 
# e2fsprogs: uclibc $(TARGET_DIR)/$(E2FSPROGS_TARGET_BINARY)
# 
# e2fsprogs-build: $(E2FSPROGS_DIR)/$(E2FSPROGS_BINARY)
# 
# e2fsprogs-configure: $(E2FSPROGS_DIR)/.configured
# 
# e2fsprogs-clean:
# 	$(MAKE1) DESTDIR=$(TARGET_DIR) CC=$(TARGET_CC) -C $(E2FSPROGS_DIR) uninstall
# 	-$(MAKE1) -C $(E2FSPROGS_DIR) clean
# 
# e2fsprogs-dirclean:
# 	rm -rf $(E2FSPROGS_DIR)
# 
# several other packages depends on this target
# libuuid: e2fsprogs
# 
# #############################################################
# #
# # Toplevel Makefile options
# #
# #############################################################
# ifeq ($(BR2_PACKAGE_E2FSPROGS),y)
# TARGETS+=e2fsprogs
# endif
