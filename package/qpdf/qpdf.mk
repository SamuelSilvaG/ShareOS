################################################################################
#
# qpdf
#
################################################################################

QPDF_VERSION = 10.5.0
QPDF_SOURCE = qpdf-$(QPDF_VERSION).tar.gz
QPDF_SITE = http://downloads.sourceforge.net/project/qpdf/qpdf/$(QPDF_VERSION)

QPDF_INSTALL_STAGING = YES
QPDF_LIBTOOL_PATCH = NO

QPDF_DEPENDENCIES = host-pkgconfig zlib jpeg

ifeq ($(BR2_USE_WCHAR),)
QPDF_CONF_ENV += CXXFLAGS="$(TARGET_CXXFLAGS) -DQPDF_NO_WCHAR_T"
endif

ifeq ($(BR2_PACKAGE_GNUTLS),y)
QPDF_CONF_OPT += --enable-crypto-gnutls
QPDF_DEPENDENCIES += gnutls
else
QPDF_CONF_OPT += --disable-crypto-gnutls
endif

ifeq ($(BR2_PACKAGE_OPENSSL),y)
QPDF_CONF_OPT += --enable-crypto-openssl
QPDF_DEPENDENCIES += openssl
else
QPDF_CONF_OPT += --disable-crypto-openssl
endif

ifeq ($(BR2_TOOLCHAIN_HAS_LIBATOMIC),y)
QPDF_CONF_ENV += LIBS=-latomic
endif

#--disable-rpath # deploys an error at install time,  non-existing libqpdf.lai (libqpdf.la exists)
QPDF_INSTALL_TARGET_OPT = DESTDIR=$(TARGET_DIR) install
QPDF_CONF_OPT = --disable-static --enable-shared \
	--with-random=/dev/urandom  --disable-crypto-openssl --disable-crypto-gnutls 

$(eval $(call AUTOTARGETS,package,qpdf))
		
