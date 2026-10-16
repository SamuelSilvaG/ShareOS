###########################################################
#
# cups-filters
#
###########################################################

CUPS_FILTERS_VERSION = 1.28.15
CUPS_FILTERS_SOURCE = cups-filters-$(CUPS_FILTERS_VERSION).tar.xz
CUPS_FILTERS_SITE = https://openprinting.org/download/cups-filters

CUPS_FILTERS_DEPENDENCIES = uclibc dbus avahi bzip2 libglib2 cups \
	libpng jpeg tiff zlib fontconfig freetype lcms2 qpdf 

CUPS_FILTERS_LIBTOOL_PATCH = NO

CUPS_FILTERS_CONF_OPT = --disable-rpath --disable-static --disable-ldap \
	--disable-poppler --enable-avahi --enable-dbus \
	--enable-driverless --enable-pclm  \
	--with-browseremoteprotocols=cups --without-php \
	--without-rcdir --without-rclevels --without-rcstart --without-rcstop
	
$(eval $(call AUTOTARGETS,package,cups-filters))

#BR_SDK_PATH=$(shell realpath $(TOPDIR)/../br-2019-sdk)
