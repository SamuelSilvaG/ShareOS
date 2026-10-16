#############################################################
#
# fontconfig
#
#############################################################

FONTCONFIG_VERSION = 2.13.1
FONTCONFIG_SOURCE = fontconfig-$(FONTCONFIG_VERSION).tar.bz2
FONTCONFIG_SITE = https://www.freedesktop.org/software/fontconfig/release/

FONTCONFIG_LIBTOOL_PATCH = NO

FONTCONFIG_INSTALL_STAGING = YES
FONTCONFIG_INSTALL_TARGET = YES

FONTCONFIG_CONF_OPT = \
	--with-arch=$(GNU_TARGET_NAME) \
	--with-cache-dir=/var/cache/fontconfig \
	--with-expat="$(STAGING_DIR)/usr/lib" \
	--with-expat-lib=$(STAGING_DIR)/usr/lib \
	--with-expat-includes=$(STAGING_DIR)/usr/include \
	--disable-docs

FONTCONFIG_DEPENDENCIES = uclibc bzip2 freetype expat

$(eval $(call AUTOTARGETS,package,fontconfig))
