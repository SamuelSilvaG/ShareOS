#############################################################
#
# sabyenc
#
############################################################

SABYENC_VERSION = 3.3.6
SABYENC_SOURCE = v$(SABYENC_VERSION).tar.gz
SABYENC_SITE = https://github.com/sabnzbd/sabyenc/archive/

SABYENC_AUTORECONF = NO
SABYENC_INSTALL_STAGING = NO
SABYENC_INSTALL_TARGET = NO
SABYENC_LIBTOOL_PATCH = NO

SABYENC_DIR:=$(BUILD_DIR)/sabyenc-$(SABYENC_VERSION)
SABYENC_CAT:=$(ZCAT)

SABYENC_BINARY:=sabyenc.so
SABYENC_SITE_PACKAGE_DIR=usr/lib/python$(PYTHON_VERSION_MAJOR)/site-packages
SABYENC_TARGET_BINARY=$(SABYENC_SITE_PACKAGE_DIR)/$(SABYENC_BINARY)

SABYENC_CFLAGS = CFLAGS+=" -I$(STAGING_DIR)/usr/include/python$(PYTHON_VERSION_MAJOR)"

$(DL_DIR)/$(SABYENC_SOURCE):
	 $(call DOWNLOAD,$(SABYENC_SITE),$(SABYENC_SOURCE))

$(SABYENC_DIR)/.unpacked: $(DL_DIR)/$(SABYENC_SOURCE)
	$(SABYENC_CAT) $(DL_DIR)/$(SABYENC_SOURCE) | tar -C $(BUILD_DIR) $(TAR_OPTIONS) -
	touch $@

$(SABYENC_DIR)/.patched: $(SABYENC_DIR)/.unpacked
	toolchain/patch-kernel.sh $(SABYENC_DIR) package/sabyenc/ sabyenc-$(SABYENC_VERSION)-\*.patch
	touch $@

$(SABYENC_DIR)/.build: $(SABYENC_DIR)/.patched
	(cd $(SABYENC_DIR); \
		$(TARGET_CONFIGURE_OPTS) $(TARGET_CONFIGURE_ENV) LDSHARED="$(TARGET_CC) -shared" $(SABYENC_CFLAGS) \
		LD_LIBRARY_PATH=$(HOST_DIR)/usr/lib/ $(HOST_DIR)/usr/bin/python setup.py \
		bdist_dumb --plat-name $(GNU_TARGET_NAME) --relative \
	)
	touch $@

$(TARGET_DIR)/$(SABYENC_TARGET_BINARY): $(SABYENC_DIR)/.build
	tar -C $(TARGET_DIR)/usr -xf $(SABYENC_DIR)/dist/sabyenc-$(SABYENC_VERSION).$(GNU_TARGET_NAME).tar.gz
	touch $(TARGET_DIR)/$(SABYENC_TARGET_BINARY)

sabyenc: python $(TARGET_DIR)/$(SABYENC_TARGET_BINARY)

sabyenc-unpack: $(SABYENC_DIR)/.unpacked

sabyenc-build: python $(SABYENC_DIR)/.build

sabyenc-install: python $(TARGET_DIR)/$(SABYENC_TARGET_BINARY)

sabyenc-dirclean:
	rm -rf $(SABYENC_DIR)

#############################################################
#
# Toplevel Makefile options
#
############################################################
ifeq ($(BR2_PACKAGE_SABYENC),y)
TARGETS+=sabyenc
endif
