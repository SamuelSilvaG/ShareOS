###########################################################
#
# wget
#
###########################################################

#WGET_VERSION:=1.21.3
WGET_VERSION:=1.24.5
WGET_SITE:=https://ftp.gnu.org/gnu/wget
WGET_SOURCE:=wget-$(WGET_VERSION).tar.gz

WGET_DIR:=$(BUILD_DIR)/wget-$(WGET_VERSION)

WGET_DEPENDENCIES = host-pkgconfig

WGET_CONF_ENV = CFLAGS="$(TARGET_CFLAGS) $(BR2_PACKAGE_WGET_OPTIM)"
WGET_CONF_OPT = -disable-pcre --disable-pcre2 \
	--with-included-libunistring --with-ssl=openssl \
	--disable-debug

ifeq ($(BR2_PACKAGE_OPENSSL),n)
	DISABLE_SSL += --without-ssl
else
	DISABLE_SSL += --with-ssl=openssl
	WGET_DEPENDENCIES += openssl
endif

$(eval $(call AUTOTARGETS,package,wget))

$(WGET_HOOK_POST_INSTALL): $(PCRE2_TARGET_INSTALL_TARGET)
	rm $(TARGET_DIR)/etc/wgetrc
	touch $@
