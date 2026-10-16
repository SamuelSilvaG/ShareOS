#############################################################
#
# libconfuse
#
#############################################################
LIBCONFUSE_VERSION:=2.8
LIBCONFUSE_SOURCE:=confuse-$(LIBCONFUSE_VERSION).tar.xz
#LIBCONFUSE_SITE:=http://bzero.se/confuse/
LIBCONFUSE_SITE:=https://github.com/libconfuse/libconfuse/releases/download/v$(LIBCONFUSE_VERSION)

LIBCONFUSE_AUTORECONF:=NO
LIBCONFUSE_LIBTOOL_PATCH = NO

LIBCONFUSE_INSTALL_STAGING:=YES
LIBCONFUSE_INSTALL_TARGET:=YES

LIBCONFUSE_CONF_OPT:=--enable-shared --disable-rpath

LIBCONFUSE_DEPENDENCIES = uclibc

$(eval $(call AUTOTARGETS,package,libconfuse))
