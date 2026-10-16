################################################################################
#
# libubox
#
################################################################################

LIBUBOX_SITE = https://git.openwrt.org/project/libubox.git
LIBUBOX_VERSION = f2d675
LIBUBOX_SOURCE = libubox-$(LIBUBOX_VERSION).tgz

LIBUBOX_COMMIT = f2d6752901f2f2d8612fb43e10061570c9198af1
LIBUBOX_SOURCE2 = "?a=snapshot;h=$(LIBUBOX_COMMIT);sf=tgz"
LIBUBOX_WGET_OPTS = -O $(DL_DIR)/libubox-$(LIBUBOX_VERSION).tgz

LIBUBOX_INSTALL_STAGING = YES
LIBUBOX_INSTALL_TARGET = NO
LIBUBOX_LIBTOOL_PATCH = NO

# Ensure directory for lockfile exists
#define LIBUBOX_CREATE_LOCKDIR
#	mkdir -p $(TARGET_DIR)/usr/lib/opkg
#endef
#
#LIBUBOX_POST_INSTALL_TARGET_HOOKS += LIBUBOX_CREATE_LOCKDIR

$(eval $(call AUTOTARGETS,package,libubox))

$(LIBUBOX_TARGET_SOURCE):
	$(call DOWNLOAD,$(LIBUBOX_SITE),$(LIBUBOX_SOURCE2), $(LIBUBOX_WGET_OPTS))
	mkdir -p $(BUILD_DIR)/libubox-$(LIBUBOX_VERSION)
	touch $@

$(LIBUBOX_TARGET_CONFIGURE): $(LIBUBOX_TARGET_PATCH)
	( cd $(LIBUBOX_DIR); \
		cmake -B build . \
		-DCMAKE_VERBOSE_MAKEFILE=yes \
		-DCMAKE_SYSTEM_NAME=Linux \
		-DCMAKE_SYSTEM_PROCESSOR=armv5l \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_COMPILER=arm-linux-gcc \
		-DCMAKE_C_FLAGS="$(TARGET_CFLAGS)" \
		-DCMAKE_C_FLAGS_DEBUG="" \
		-DCMAKE_SYSROOT="$(STAGING_DIR)" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_FIND_ROOT_PATH="$(STAGING_DIR)" s\
		-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
		-DBUILD_LUA=OFF \
		-DBUILD_EXAMPLES=OFF \
	)
	touch $@

$(LIBUBOX_TARGET_BUILD):
	make -C $(LIBUBOX_DIR)/build ubox-static
	touch $@

$(LIBUBOX_TARGET_INSTALL_STAGING):
	make DESTDIR=$(STAGING_DIR) -C $(LIBUBOX_DIR)/build install/strip
	touch $@

$(LIBUBOX_TARGET_CLEAN):
	make -C $(LIBUBOX_DIR)/build clean
	rm -f $(LIBUBOX_DIR)/.stamp_configured
	touch $@
