#############################################################
#
# libgd
#
#############################################################

#LIBGD_VERSION:=2.0.33
#LIBGD_SITE:=https://bitbucket.org/libgd/gd-libgd/get
#LIBGD_SOURCE=GD_$(subst .,_,$(LIBGD_VERSION)).tar.bz2
#LIBGD_SUBDIR = src

LIBGD_VERSION:=2.3.3
LIBGD_SITE = https://github.com/libgd/libgd/releases/download/gd-$(LIBGD_VERSION)
LIBGD_SOURCE = libgd-$(LIBGD_VERSION).tar.xz

LIBGD_LIBTOOL_PATCH = NO
LIBGD_INSTALL_STAGING = YES

LIBGD_DEPENDENCIES = libpng jpeg
LIBGD_CONF_OPT = --disable-rpath --without-freetype --without-fontconfig --without-xpm

$(eval $(call AUTOTARGETS,package,libgd))

# configure leak, CPPFLAGS points to /usr/include, remove it
# $(LIBGD_HOOK_POST_CONFIGURE):
# 	sed -i 's|^CPPFLAGS.*||' $(LIBGD_DIR)/$(LIBGD_SUBDIR)/Makefile
# 	touch $@
# 
# $(LIBGD_HOOK_POST_INSTALL):
# 	sed -i "s|^prefix=/usr|prefix=$(STAGING_DIR)/usr|" $(STAGING_DIR)/usr/bin/gdlib-config
# 	rm -f $(TARGET_DIR)/usr/bin/gdlib-config
# 	touch $@
