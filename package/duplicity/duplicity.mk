#############################################################
#
# duplicity
#
############################################################

DUPLICITY_VERSION:=0.8.16
DUPLICITY_SITE:=https://gitlab.com/duplicity/duplicity/-/archive/rel.$(DUPLICITY_VERSION)
DUPLICITY_SOURCE:=duplicity-rel.$(DUPLICITY_VERSION).tar.bz2
DUPLICITY_DIR:=$(BUILD_DIR)/duplicity-$(DUPLICITY_VERSION)

DUPLICITY_LIBTOOL_PATCH = NO
DUPLICITY_INSTALL_STAGING = NO

DUPLICITY_DEPENDENCIES = librsync gnupg python pycrypto cryptography

DUPLICITY_CFLAGS = CFLAGS+=" -I$(STAGING_DIR)/usr/include/python$(PYTHON_VERSION_MAJOR)"
DUPLICITY_SITE_PACKAGE_DIR=usr/lib/python$(PYTHON_VERSION_MAJOR)/site-packages/duplicity

$(eval $(call AUTOTARGETS,package,duplicity))

$(DUPLICITY_TARGET_CONFIGURE):
	touch $@

$(DUPLICITY_TARGET_BUILD):
	pip install setuptools-scm==3.4.3
	(cd $(DUPLICITY_DIR); \
		$(TARGET_CONFIGURE_OPTS) $(TARGET_CONFIGURE_ENV) LDSHARED="$(TARGET_CC) -shared" $(DUPLICITY_CFLAGS) \
		LD_LIBRARY_PATH=$(HOST_DIR)/usr/lib/ $(HOST_DIR)/usr/bin/python setup.py \
		bdist_dumb --plat-name $(GNU_TARGET_NAME) --relative \
	)
	touch $@

$(DUPLICITY_TARGET_INSTALL_TARGET):
	tar -C $(TARGET_DIR)/usr -xf $(DUPLICITY_DIR)/dist/duplicity-$(DUPLICITY_VERSION).$(GNU_TARGET_NAME).tar.gz
	find $(TARGET_DIR)/$(DUPLICITY_SITE_PACKAGE_DIR) -name \*.pyc -delete
	for i in duplicity rdiffdir; do \
		sed -i '1s|^.*$$|#!/usr/bin/python|' $(TARGET_DIR)/usr/bin/$$i; \
	done
	touch $@
