#############################################################
#
# tiff
#
#############################################################

#TIFF_VERSION:=3.9.7
TIFF_VERSION:=4.5.1
#TIFF_SITE:=ftp://ftp.remotesensing.org/pub/libtiff
TIFF_SITE:=https://download.osgeo.org/libtiff
# 3.9.7.tar.gz, 4.0.10.tar.gz (suse uses),... up to 4.6 
TIFF_SOURCE:=tiff-$(TIFF_VERSION).tar.gz

TIFF_LIBTOOL_PATCH = NO
TIFF_INSTALL_STAGING = YES
TIFF_INSTALL_TARGET = YES
TIFF_CONF_OPT = \
	--enable-shared \
	--disable-static \
	--without-x \
	--program-prefix=""

TIFF_DEPENDENCIES = uclibc host-pkgconfig zlib jpeg

$(eval $(call AUTOTARGETS,package,tiff))
