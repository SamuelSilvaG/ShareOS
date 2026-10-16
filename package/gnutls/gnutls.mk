################################################################################
#
# gnutls
#
################################################################################

# When bumping, make sure *all* --without-libfoo-prefix options are in GNUTLS_CONF_OPT
GNUTLS_VERSION2_MAJOR = 3.7
GNUTLS_VERSION = 3.7.4
GNUTLS_SOURCE = gnutls-$(GNUTLS_VERSION).tar.xz
GNUTLS_SITE = https://www.gnupg.org/ftp/gcrypt/gnutls/v$(GNUTLS_VERSION2_MAJOR)

GNUTLS_DEPENDENCIES = host-pkgconfig zlib libtasn1 libunistring nettle
GNUTLS_LIBTOOL_PATCH = NO
GNUTLS_INSTALL_STAGING = YES

GNUTLS_CONF_OPT = \
	--disable-doc \
	--disable-guile \
	--disable-libdane \
	--disable-rpath \
	--disable-tests \
	--without-included-unistring \
	--without-libcrypto-prefix \
	--without-libdl-prefix \
	--without-libev-prefix \
	--without-libiconv-prefix \
	--without-libintl-prefix \
	--without-libpthread-prefix \
	--without-libseccomp-prefix \
	--without-librt-prefix \
	--without-libz-prefix \
	--without-tpm \
	--with-nettle-mini \
	$(if $(BR2_PACKAGE_GNUTLS_TOOLS),--enable-tools,--disable-tools) \
	$(if $(BR2_PACKAGE_GNUTLS_ENABLE_SSL2),--enable,--disable)-ssl2-support \
	$(if $(BR2_PACKAGE_GNUTLS_ENABLE_GOST),--enable,--disable)-gost
	
GNUTLS_CONF_ENV = gl_cv_socket_ipv6=yes \
	ac_cv_header_wchar_h=$(if $(BR2_USE_WCHAR),yes,no) \
	gt_cv_c_wchar_t=$(if $(BR2_USE_WCHAR),yes,no) \
	gt_cv_c_wint_t=$(if $(BR2_USE_WCHAR),yes,no) \
	gl_cv_func_gettimeofday_clobber=no

ifeq ($(BR2_PACKAGE_GNUTLS_OPENSSL),y)
GNUTLS_LICENSE += , GPL-3.0+ (gnutls-openssl library)
GNUTLS_LICENSE_FILES += doc/COPYING
GNUTLS_CONF_OPT += --enable-openssl-compatibility
else
GNUTLS_CONF_OPT += --disable-openssl-compatibility
endif

ifeq ($(BR2_PACKAGE_BROTLI),y)
GNUTLS_CONF_OPT += --with-libbrotli
GNUTLS_DEPENDENCIES += brotli
else
GNUTLS_CONF_OPT += --without-libbrotli
endif

ifeq ($(BR2_PACKAGE_CRYPTODEV),y)
GNUTLS_CONF_OPT += --enable-cryptodev
GNUTLS_DEPENDENCIES += cryptodev
endif

ifeq ($(BR2_PACKAGE_LIBIDN2),y)
GNUTLS_CONF_OPT += --with-idn
GNUTLS_DEPENDENCIES += libidn2
else
GNUTLS_CONF_OPT += --without-idn
endif

ifeq ($(BR2_PACKAGE_P11_KIT),y)
GNUTLS_CONF_OPT += --with-p11-kit
GNUTLS_DEPENDENCIES += p11-kit
else
GNUTLS_CONF_OPT += --without-p11-kit
endif

ifeq ($(BR2_PACKAGE_ZLIB),y)
GNUTLS_CONF_OPT += --with-zlib
GNUTLS_DEPENDENCIES += zlib
else
GNUTLS_CONF_OPT += --without-zlib
endif

ifeq ($(BR2_PACKAGE_ZSTD),y)
GNUTLS_CONF_OPT += --with-libzstd
GNUTLS_DEPENDENCIES += zstd
else
GNUTLS_CONF_OPT += --without-libzstd
endif

# Provide a default CA cert location
ifeq ($(BR2_PACKAGE_P11_KIT),y)
GNUTLS_CONF_OPT += --with-default-trust-store-pkcs11=pkcs11:model=p11-kit-trust
else ifeq ($(BR2_PACKAGE_CA_CERTIFICATES),y)
GNUTLS_CONF_OPT += --with-default-trust-store-file=/etc/ssl/certs/ca-certificates.crt
endif

ifeq ($(BR2_TOOLCHAIN_HAS_LIBATOMIC),y)
GNUTLS_LIBS += -latomic
endif

GNUTLS_CONF_ENV += LIBS="$(GNUTLS_LIBS)"
GNUTLS_CONF_ENV += CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include"

$(eval $(call AUTOTARGETS,package,gnutls))
