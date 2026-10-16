################################################################################
#
# opkg
#
################################################################################

OPKG_VERSION = 0.4.5
OPKG_SITE = https://downloads.yoctoproject.org/releases/opkg
OPKG_DEPENDENCIES = host-pkgconfig libarchive
OPKG_INSTALL_STAGING = NO
OPKG_LIBTOOL_PATCH = NO
OPKG_CONF_OPT = --disable-curl --disable-openssl --disable-gpg --disable-xz \
	--with-static-libopkg --disable-shared

# Ensure directory for lockfile exists
#define OPKG_CREATE_LOCKDIR
#	mkdir -p $(TARGET_DIR)/usr/lib/opkg
#endef
#
#OPKG_POST_INSTALL_TARGET_HOOKS += OPKG_CREATE_LOCKDIR

$(eval $(call AUTOTARGETS,package,opkg))

