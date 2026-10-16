#############################################################
#
# nzbget
#
#############################################################

# versions since 17.0 needs C++14 compiler support, which gcc-4.3.3 has not
NZBGET_VERSION = 16.4
NZBGET_SOURCE = nzbget-$(NZBGET_VERSION)-src.tar.gz
NZBGET_SITE = https://github.com/nzbget/nzbget/releases/download/v$(NZBGET_VERSION)

NZBGET_AUTORECONF = NO
NZBGET_INSTALL_STAGING = NO
NZBGET_INSTALL_TARGET = YES
NZBGET_LIBTOOL_PATCH = NO
NZBGET_DEPENDENCIES = uclibc libpar2 libxml2 openssl-compat ncurses p7zip unrar

NZBGET_CONF_OPT = --program-prefix="" \
	--with-openssl-includes=$(STAGING_DIR)/compat/usr/include \
	--with-openssl-libraries=$(STAGING_DIR)/compat/usr/lib
NZBGET_CONF_ENV = LIBPREF=$(STAGING_DIR) \
	libxml2_CFLAGS="-I$(STAGING_DIR)/usr/include/libxml2" \
	libxml2_LIBS="-L$(STAGING_DIR)/usr/lib -lxml2" \
	CFLAGS="-I$(STAGING_DIR)/compat/usr/include $(TARGET_CFLAGS)" \
	CXXFLAGS="-I$(STAGING_DIR)/compat/usr/include $(TARGET_CXXFLAGS)" \
	LDFLAGS="-L$(STAGING_DIR)/compat/usr/lib $(TARGET_LDFLAGS)"

$(eval $(call AUTOTARGETS,package,nzbget))

$(NZBGET_HOOK_POST_INSTALL):
	$(RM) $(TARGET_DIR)/usr/sbin/nzbgetd
	touch $@
