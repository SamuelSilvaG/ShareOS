################################################################################
#
# opkg-lede
#
################################################################################

# not properly working

OPKG_LEDE_SITE = https://git.openwrt.org/project/opkg-lede.git
OPKG_LEDE_VERSION = d038e5b
OPKG_LEDE_SOURCE = opkg-lede-$(OPKG_LEDE_VERSION).tgz

OPKG_LEDE_COMMIT = d038e5b6d155784575f62a66a8bb7e874173e92e
OPKG_LEDE_SOURCE2 = "?a=snapshot;h=$(OPKG_LEDE_COMMIT);sf=tgz"
OPKG_LEDE_WGET_OPTS = -O $(DL_DIR)/opkg-lede-$(OPKG_LEDE_VERSION).tgz

OPKG_LEDE_DEPENDENCIES = host-pkgconfig libubox
OPKG_LEDE_INSTALL_STAGING = NO
OPKG_LEDE_LIBTOOL_PATCH = NO

# Ensure directory for lockfile exists
#define OPKG_LEDE_CREATE_LOCKDIR
#	mkdir -p $(TARGET_DIR)/usr/lib/opkg
#endef
#
#OPKG_LEDE_POST_INSTALL_TARGET_HOOKS += OPKG_LEDE_CREATE_LOCKDIR

$(eval $(call AUTOTARGETS,package,opkg-lede))

$(OPKG_LEDE_TARGET_SOURCE):
	$(call DOWNLOAD,$(OPKG_LEDE_SITE),$(OPKG_LEDE_SOURCE2), $(OPKG_LEDE_WGET_OPTS))
	mkdir -p $(BUILD_DIR)/opkg-lede-$(OPKG_LEDE_VERSION)
	touch $@

$(OPKG_LEDE_TARGET_CONFIGURE):
	( cd $(OPKG_LEDE_DIR); \
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
		-DCMAKE_FIND_ROOT_PATH="$(STAGING_DIR)" \
		-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
		-DENABLE_USIGN=OFF \
		-DBUILD_TESTS=OFF \
		-DSTATIC_UBOX=ON \
	)
	touch $@

$(OPKG_LEDE_TARGET_BUILD):
	make -C $(OPKG_LEDE_DIR)/build opkg
	touch $@

$(OPKG_LEDE_TARGET_INSTALL_TARGET):
	make DESTDIR=$(TARGET_DIR) -C $(OPKG_LEDE_DIR)/build install/strip
	touch $@

$(OPKG_LEDE_TARGET_CLEAN):
	make -C $(OPKG_LEDE_DIR)/build clean
	rm -f $(OPKG_LEDE_DIR)/.stamp_configured
	touch $@
