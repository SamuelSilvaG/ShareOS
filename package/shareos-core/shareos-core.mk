################################################################################
#
# shareos-core
#
################################################################################

SHAREOS_CORE_VERSION = 0.1
SHAREOS_CORE_SITE = $(BR2_EXTERNAL_SHAREOS_PATH)/src/shareos-core
SHAREOS_CORE_SITE_METHOD = local
SHAREOS_CORE_LICENSE = GPL-2.0+
SHAREOS_CORE_DEPENDENCIES = uci ubus ucode rpcd uhttpd libcurl alt-f-utils

define SHAREOS_CORE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/etc/config/shareos $(TARGET_DIR)/etc/config/shareos
	$(INSTALL) -D -m 0600 $(@D)/etc/config/rpcd $(TARGET_DIR)/etc/config/rpcd
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/S12ubus $(TARGET_DIR)/etc/init.d/S12ubus
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/S13rpcd $(TARGET_DIR)/etc/init.d/S13rpcd
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/S50uhttpd $(TARGET_DIR)/etc/init.d/S50uhttpd
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-update $(TARGET_DIR)/usr/sbin/shareos-update
	$(INSTALL) -D -m 0644 $(@D)/usr/share/rpcd/ucode/shareos.uc $(TARGET_DIR)/usr/share/rpcd/ucode/shareos.uc
	$(INSTALL) -D -m 0644 $(@D)/usr/share/rpcd/acl.d/shareos.json $(TARGET_DIR)/usr/share/rpcd/acl.d/shareos.json
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-factory-reset $(TARGET_DIR)/usr/sbin/shareos-factory-reset
	rm -rf $(TARGET_DIR)/www
	cp -a $(@D)/www $(TARGET_DIR)/www
endef

$(eval $(generic-package))
