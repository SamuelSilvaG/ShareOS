#############################################################
#
# yenc
#
############################################################

YENC_VERSION = 0.4.0
#YENC_SOURCE = python-yenc_$(YENC_VERSION).orig.tar.gz
#YENC_SITE = http://deb.debian.org/debian/pool/main/p/python-yenc
YENC_SITE = https://pypi.org/packages/source/y/yenc
YENC_SOURCE = yenc-$(YENC_VERSION).tar.gz

YENC_AUTORECONF = NO
YENC_INSTALL_STAGING = NO
YENC_INSTALL_TARGET = NO
YENC_LIBTOOL_PATCH = NO

YENC_DIR:=$(BUILD_DIR)/yenc-$(YENC_VERSION)
YENC_CAT:=$(ZCAT)

YENC_BINARY:=_yenc.so
YENC_SITE_PACKAGE_DIR = usr/lib/python$(PYTHON_VERSION_MAJOR)/site-packages
YENC_TARGET_BINARY = $(YENC_SITE_PACKAGE_DIR)/$(YENC_BINARY)

YENC_CFLAGS = CFLAGS+=" -I$(STAGING_DIR)/usr/include/python$(PYTHON_VERSION_MAJOR)"

$(DL_DIR)/$(YENC_SOURCE):
	 $(call DOWNLOAD,$(YENC_SITE),$(YENC_SOURCE))

$(YENC_DIR)/.unpacked: $(DL_DIR)/$(YENC_SOURCE)
	$(YENC_CAT) $(DL_DIR)/$(YENC_SOURCE) | tar -C $(BUILD_DIR) $(TAR_OPTIONS) -
	touch $@

$(YENC_DIR)/.patched: $(YENC_DIR)/.unpacked
	toolchain/patch-kernel.sh $(YENC_DIR) package/yenc/ yenc-$(YENC_VERSION)-\*.patch
	touch $@

$(YENC_DIR)/.build: $(YENC_DIR)/.patched
	(cd $(YENC_DIR); \
		$(TARGET_CONFIGURE_OPTS) $(TARGET_CONFIGURE_ENV) LDSHARED="$(TARGET_CC) -shared" $(YENC_CFLAGS) \
		LD_LIBRARY_PATH=$(HOST_DIR)/usr/lib/ $(HOST_DIR)/usr/bin/python setup.py \
		bdist_dumb --plat-name $(GNU_TARGET_NAME) --relative \
	)
	touch $@

$(TARGET_DIR)/$(YENC_TARGET_BINARY): $(YENC_DIR)/.build
	tar -C $(TARGET_DIR)/usr -xf $(YENC_DIR)/dist/yenc-$(YENC_VERSION).$(GNU_TARGET_NAME).tar.gz
	rm $(TARGET_DIR)/$(YENC_SITE_PACKAGE_DIR)/yenc.pyc
	touch $(TARGET_DIR)/$(YENC_TARGET_BINARY)

yenc: python $(TARGET_DIR)/$(YENC_TARGET_BINARY)

yenc-unpack: $(YENC_DIR)/.unpacked

yenc-build: python $(YENC_DIR)/.build

yenc-install: python $(TARGET_DIR)/$(YENC_TARGET_BINARY)

yenc-dirclean:
	rm -rf $(YENC_DIR)

#############################################################
#
# Toplevel Makefile options
#
############################################################
ifeq ($(BR2_PACKAGE_YENC),y)
TARGETS+=yenc
endif
