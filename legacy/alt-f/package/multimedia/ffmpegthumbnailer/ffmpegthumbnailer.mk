#############################################################
#
# ffmpegthumbnailer
#
#############################################################

# 2.0.9 and later requires cmake and a -std=c++11 gcc compiler

FFMPEGTHUMBNAILER_VERSION = 2.0.10
FFMPEGTHUMBNAILER_SOURCE = ffmpegthumbnailer-$(FFMPEGTHUMBNAILER_VERSION).tar.bz2
#FFMPEGTHUMBNAILER_SITE = https://github.com/dirkvdb/ffmpegthumbnailer/archive
FFMPEGTHUMBNAILER_SITE = https://github.com/dirkvdb/ffmpegthumbnailer/releases/download/$(FFMPEGTHUMBNAILER_VERSION)

FFMPEGTHUMBNAILER_AUTORECONF = YES
FFMPEGTHUMBNAILER_LIBTOOL_PATCH = NO

FFMPEGTHUMBNAILER_INSTALL_STAGING = YES
FFMPEGTHUMBNAILER_INSTALL_TARGET = YES

FFMPEGTHUMBNAILER_DEPENDENCIES = uclibc ffmpeg jpeg libpng

FFMPEGTHUMBNAILER_CONF_OPT = --disable-static --enable-png --enable-jpeg
FFMPEGTHUMBNAILER_CONF_ENV = PKG_CONFIG_PATH=$(STAGING_DIR)/usr/lib/pkgconfig/ LIBS="-lpthread"

$(eval $(call AUTOTARGETS,package/multimedia,ffmpegthumbnailer))

$(FFMPEGTHUMBNAILER_HOOK_POST_EXTRACT):
	mkdir -p $(FFMPEGTHUMBNAILER_DIR)/m4
