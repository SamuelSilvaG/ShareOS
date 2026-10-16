#############################################################
#
# libffi
#
############################################################

LIBFFI_VERSION = 3.4.2
LIBFFI_SOURCE = libffi-$(LIBFFI_VERSION).tar.gz
LIBFFI_SITE = https://github.com/libffi/libffi/releases/download/v$(LIBFFI_VERSION)

LIBFFI_LIBTOOL_PATCH = NO
LIBFFI_INSTALL_STAGING = YES
LIBFFI_INSTALL_TARGET = YES

#--disable-multi-os-directory
LIBFFI_CONF_OPT = --disable-static --disable-builddir --with-sysroot=$(STAGING_DIR)
LIBFFI_HOST_CONF_OPT = --disable-static --disable-multi-os-directory
LIBFFI_DEPENDENCIES = uclibc libffi-host

$(eval $(call AUTOTARGETS,package,libffi))
$(eval $(call AUTOTARGETS_HOST,package,libffi))
