#############################################################
#
# mxml
#
#############################################################

MXML_VERSION:=2.12
MXML_SITE = https://github.com/michaelrsweet/mxml/releases/download/v$(MXML_VERSION)
MXML_SOURCE =mxml-$(MXML_VERSION).tar.gz

MXML_DIR=$(BUILD_DIR)/mxml-$(MXML_VERSION)

MXML_LIBTOOL_PATCH = NO
MXML_INSTALL_STAGING = YES
MXML_INSTALL_TARGET = YES

MXML_INSTALL_TARGET_OPT = DSTROOT=$(TARGET_DIR) install
MXML_INSTALL_STAGING_OPT = DSTROOT=$(STAGING_DIR) install

MXML_CONF_OPT = --disable-static --enable-shared

$(eval $(call AUTOTARGETS,package,mxml))

$(MXML_HOOK_POST_INSTALL):
	-rm $(TARGET_DIR)//usr/bin/mxmldoc
	touch $@
