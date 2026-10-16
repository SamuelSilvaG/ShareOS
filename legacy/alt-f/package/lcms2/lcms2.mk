################################################################################
#
# lcms2
#
################################################################################

LCMS2_VERSION = 2.13
LCMS2_SITE = http://downloads.sourceforge.net/project/lcms/lcms/$(LCMS2_VERSION)
LCMS2_SOURCE = lcms2-$(LCMS2_VERSION).tar.gz

LCMS2_LIBTOOL_PATCH = NO
LCMS2_INSTALL_STAGING = YES

ifeq ($(BR2_PACKAGE_TIFF),y)
LCMS2_CONF_OPT += --with-tiff
LCMS2_DEPENDENCIES += tiff
else
LCMS2_CONF_OPT += --without-tiff
endif

ifeq ($(BR2_PACKAGE_JPEG),y)
LCMS2_CONF_OPT += --with-jpeg
LCMS2_DEPENDENCIES += jpeg
else
LCMS2_CONF_OPT += --without-jpeg
endif

ifeq ($(BR2_PACKAGE_ZLIB),y)
LCMS2_CONF_OPT += --with-zlib
LCMS2_DEPENDENCIES += zlib
else
LCMS2_CONF_OPT += --without-zlib
endif

$(eval $(call AUTOTARGETS,package,lcms2))
$(eval $(call AUTOTARGETS_HOST,package,lcms2))


