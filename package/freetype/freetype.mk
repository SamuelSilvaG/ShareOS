################################################################################
#
# freetype
#
################################################################################

FREETYPE_VERSION = 2.12.1
FREETYPE_SOURCE = freetype-$(FREETYPE_VERSION).tar.xz
#FREETYPE_SITE = http://download.savannah.gnu.org/releases/freetype
FREETYPE_SITE = https://sourceforge.net/projects/freetype/files/freetype2/$(FREETYPE_VERSION)

FREETYPE_LIBTOOL_PATCH = NO
FREETYPE_INSTALL_STAGING = YES

FREETYPE_DEPENDENCIES = host-pkgconfig
FREETYPE_CONFIG_SCRIPTS = freetype-config

FREETYPE_HOST_DEPENDENCIES = host-pkgconfig
FREETYPE_HOST_CONF_OPT = \
	--enable-freetype-config \
	--without-brotli \
	--without-bzip2 \
	--without-harfbuzz \
	--without-png \
	--without-zlib

# harfbuzz already depends on freetype so disable harfbuzz in freetype to avoid
# a circular dependency

FREETYPE_MAKE_OPT = CCexe="$(HOSTCC)"
FREETYPE_INSTALL_TARGET_OPT = DESTDIR=$(TARGET_DIR) install

FREETYPE_CONF_OPT = --without-harfbuzz --enable-freetype-config

ifeq ($(BR2_PACKAGE_LIBPNG),y)
FREETYPE_DEPENDENCIES += libpng
FREETYPE_CONF_ENV += LIBPNG_CFLAGS="-I$(STAGING_DIR)/usr/include"
FREETYPE_CONF_ENV += LIBPNG_LIBS="-L$(STAGING_DIR)/usr/lib -lpng"
FREETYPE_CONF_OPT += --with-png
else
FREETYPE_CONF_OPT += --without-png
endif

ifeq ($(BR2_PACKAGE_ZLIB),y)
FREETYPE_DEPENDENCIES += zlib
FREETYPE_CONF_OPT += --with-zlib
FREETYPE_CONF_ENV += ZLIB_CFLAGS="-I$(STAGING_DIR)/usr/include"
FREETYPE_CONF_ENV += ZLIB_LIBS="-L$(STAGING_DIR)/usr/lib -lz"
else
FREETYPE_CONF_OPT += --without-zlib
endif

ifeq ($(BR2_PACKAGE_BROTLI),y)
FREETYPE_DEPENDENCIES += brotli
FREETYPE_CONF_OPT += --with-brotli
else
FREETYPE_CONF_OPT += --without-brotli
endif

ifeq ($(BR2_PACKAGE_BZIP2),y)
FREETYPE_DEPENDENCIES += bzip2
FREETYPE_CONF_OPT += --with-bzip2
FREETYPE_CONF_ENV += BZIP2_CFLAGS="-I$(STAGING_DIR)/usr/include"
FREETYPE_CONF_ENV += BZIP2_LIBS="-L$(STAGING_DIR)/usr/lib -lbz2"
else
FREETYPE_CONF_OPT += --without-bzip2
endif

$(eval $(call AUTOTARGETS,package,freetype))
$(eval $(call AUTOTARGETS_HOST,package,freetype))

# Extra fixing since includedir and libdir are expanded from configure values
$(FREETYPE_HOOK_POST_INSTALL):
	$(SED) 's:^includedir=.*:includedir="$${prefix}/include":' \
		-e 's:^libdir=.*:libdir="$${exec_prefix}/lib":' \
		$(STAGING_DIR)/usr/bin/freetype-config
	$(RM) $(TARGET_DIR)/usr/bin/freetype-config
	touch $@
