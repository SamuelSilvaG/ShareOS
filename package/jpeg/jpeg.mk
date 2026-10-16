#############################################################
#
# jpeg (libraries needed by some apps)
#
#############################################################

JPEG_VERSION:=9e
JPEG_SITE:=https://www.ijg.org/files/
JPEG_SOURCE=jpegsrc.v$(JPEG_VERSION).tar.gz

JPEG_DIR=$(BUILD_DIR)/jpeg-$(JPEG_VERSION)

JPEG_LIBTOOL_PATCH = NO
JPEG_INSTALL_STAGING = YES

JPEG_PROGS = cjpeg djpeg jpegtran rdjpgcom wrjpgcom 

JPEG_CONF_OPT = --disable-static --program-prefix=""

$(eval $(call AUTOTARGETS,package,jpeg))
$(eval $(call AUTOTARGETS_HOST,package,jpeg))

define JPEG_PC
prefix=/usr
exec_prefix=/usr
libdir=/usr/lib
includedir=/usr/include

Name: libjpeg
Description: A JPEG codec that provides the libjpeg API
Version: 8c
Libs: -L$${libdir} -ljpeg
Cflags: -I$${includedir}
endef

export JPEG_PC

$(JPEG_HOOK_POST_INSTALL):
	#echo "$$JPEG_PC" > $(STAGING_DIR)/usr/lib/pkgconfig/libjpeg.pc
ifneq ($(BR2_PACKAGE_JPEG_PROGS),y)
	(cd $(TARGET_DIR)/usr/bin; rm -f $(JPEG_PROGS))
endif
	touch $@
