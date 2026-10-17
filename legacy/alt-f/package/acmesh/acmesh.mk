#############################################################
#
# acme.sh
#
#############################################################

ACMESH_VERSION:=2.8.6
ACMESH_SOURCE:=$(ACMESH_VERSION).tar.gz
ACMESH_SITE:=https://github.com/acmesh-official/acme.sh/archive

ACMESH_LIBTOOL_PATCH = NO
ACMESH_DEPENDENCIES = openssl lighttpd

$(eval $(call AUTOTARGETS,package,acmesh))

$(ACMESH_TARGET_SOURCE):
	$(call DOWNLOAD,$(ACMESH_SITE),$(ACMESH_SOURCE))
	(cd $(DL_DIR); ln -sf $(ACMESH_SOURCE) acmesh-$(ACMESH_SOURCE))
	mkdir -p $(BUILD_DIR)/acmesh-$(ACMESH_VERSION)
	touch $@

$(ACMESH_TARGET_CONFIGURE):
	touch $@

$(ACMESH_TARGET_BUILD):
	touch $@
	
$(ACMESH_TARGET_INSTALL_TARGET):
	mkdir -p $(TARGET_DIR)/usr/share/acme.sh
	cd $(ACMESH_DIR) && cp -r acme.sh notify deploy dnsapi $(TARGET_DIR)/usr/share/acme.sh/
	touch $@

