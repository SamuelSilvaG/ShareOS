#############################################################
#
# lighttpd
#
#############################################################

LIGHTTPD_VERSION = 1.4.64
LIGHTTPD_SOURCE = lighttpd-$(LIGHTTPD_VERSION).tar.xz
LIGHTTPD_SITE = https://download.lighttpd.net/lighttpd/releases-1.4.x

LIGHTTPD_LIBTOOL_PATCH = NO
LIGHTTPD_DEPENDENCIES = uclibc

ifneq ($(BR2_LARGEFILE),y)
LIGHTTPD_LFS:=$(DISABLE_LARGEFILE) --disable-lfs
endif

LIGHTTPD_CONF_OPT = \
	--libdir=/usr/lib/lighttpd \
	--libexecdir=/usr/lib \
	--localstatedir=/var \
	--program-prefix="" \
	$(DISABLE_IPV6) \
	$(LIGHTTPD_LFS)

ifeq ($(BR2_PACKAGE_LIGHTTPD_OPENSSL),y)
LIGHTTPD_DEPENDENCIES += openssl
LIGHTTPD_CONF_OPT += --with-openssl
else
LIGHTTPD_CONF_OPT += --without-openssl
endif

ifeq ($(BR2_PACKAGE_LIGHTTPD_ZLIB),y)
LIGHTTPD_DEPENDENCIES += zlib
LIGHTTPD_CONF_OPT += --with-zlib
else
LIGHTTPD_CONF_OPT += --without-zlib
endif

ifeq ($(BR2_PACKAGE_LIGHTTPD_BZIP2),y)
LIGHTTPD_DEPENDENCIES += bzip2
LIGHTTPD_CONF_OPT += --with-bzip2
else
LIGHTTPD_CONF_OPT += --without-bzip2
endif

ifeq ($(BR2_PACKAGE_LIGHTTPD_PCRE2),y)
LIGHTTPD_CONF_ENV += PCRE2_LIB="-lpcre2"
LIGHTTPD_DEPENDENCIES += pcre2
LIGHTTPD_CONF_OPT += --with-pcre2
else
LIGHTTPD_CONF_OPT += --without-pcre2
endif

ifeq ($(BR2_PACKAGE_LIGHTTPD_WEBDAV),y)
LIGHTTPD_DEPENDENCIES += sqlite libxml2 e2fsprogs libiconv xz
LIGHTTPD_CONF_OPT += --with-webdav-props --with-webdav-locks
LIGHTTPD_CONF_ENV += LIBS="-lpthread"
endif

$(eval $(call AUTOTARGETS,package,lighttpd))

#$(LIGHTTPD_HOOK_POST_CONFIGURE):
#	sed -i '/^#define HAVE_SENDFILE_BROKEN/d' $(LIGHTTPD_DIR)/config.h

$(LIGHTTPD_HOOK_POST_INSTALL):
	mkdir -p $(TARGET_DIR)/etc/lighttpd
	cp -a $(LIGHTTPD_DIR)/doc/config/* $(TARGET_DIR)/etc/lighttpd
	find $(TARGET_DIR)/etc/lighttpd -name Makefile\* -delete
	touch $@

$(LIGHTTPD_TARGET_UNINSTALL):
	$(call MESSAGE,"Uninstalling")
	rm -f $(TARGET_DIR)/usr/sbin/lighttpd
	rm -f $(TARGET_DIR)/usr/sbin/lighttpd-angel
	rm -rf $(TARGET_DIR)/usr/lib/lighttpd
	rm -f $(LIGHTTPD_TARGET_INSTALL_TARGET) $(LIGHTTPD_HOOK_POST_INSTALL)
	touch $@
