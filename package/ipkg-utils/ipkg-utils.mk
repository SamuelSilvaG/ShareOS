#############################################################
#
# ipkg-utils for the host
#
#############################################################

IPKG_UTILS_VERSION = 050831
IPKG_UTILS_SOURCE = ipkg-utils-$(IPKG_UTILS_VERSION).tar.gz
IPKG_UTILS_SITE = https://ftp.gwdg.de/pub/linux/handhelds/packages/ipkg-utils

IPKG_UTILS_DEPENDENCIES = uclibc

$(eval $(call AUTOTARGETS_HOST,package,ipkg-utils))

$(IPKG_UTILS_HOST_HOOK_POST_EXTRACT):
	toolchain/patch-kernel.sh $(IPKG_UTILS_HOST_DIR) package/ipkg-utils ipkg-utils-\*.patch
	touch $@

$(IPKG_UTILS_HOST_CONFIGURE):
	touch $@

$(IPKG_UTILS_HOST_BUILD):
	touch $@

$(IPKG_UTILS_HOST_INSTALL):
	( cd $(IPKG_UTILS_HOST_DIR); \
		cp ipkg-build ipkg-make-index ipkg.py $(HOST_DIR)/usr/bin \
	)
	touch $@
