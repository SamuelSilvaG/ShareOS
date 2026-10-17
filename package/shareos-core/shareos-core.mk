################################################################################
#
# shareos-core
#
################################################################################

SHAREOS_CORE_VERSION = 0.1
SHAREOS_CORE_SITE = $(BR2_EXTERNAL_SHAREOS_PATH)/src/shareos-core
SHAREOS_CORE_SITE_METHOD = local
SHAREOS_CORE_LICENSE = GPL-2.0+
SHAREOS_CORE_DEPENDENCIES = uci ubus ucode rpcd uhttpd libcurl alt-f-utils mbedtls
# our S40network replaces the one from ifupdown-scripts, so install after it
ifeq ($(BR2_PACKAGE_IFUPDOWN_SCRIPTS),y)
SHAREOS_CORE_DEPENDENCIES += ifupdown-scripts
endif
# same for rcS (skips services with autostart off)
ifeq ($(BR2_PACKAGE_INITSCRIPTS),y)
SHAREOS_CORE_DEPENDENCIES += initscripts
endif

# password encryption for settings backups (AES-256-GCM via mbedTLS)
define SHAREOS_CORE_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -o $(@D)/shareos-crypt $(@D)/src/shareos-crypt.c -lmbedcrypto
endef

define SHAREOS_CORE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/shareos-crypt $(TARGET_DIR)/usr/sbin/shareos-crypt
	$(INSTALL) -D -m 0644 $(@D)/etc/config/shareos $(TARGET_DIR)/etc/config/shareos
	$(INSTALL) -D -m 0600 $(@D)/etc/config/rpcd $(TARGET_DIR)/etc/config/rpcd
	$(INSTALL) -D -m 0644 $(@D)/etc/config/storage $(TARGET_DIR)/etc/config/storage
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/S20storage $(TARGET_DIR)/etc/init.d/S20storage
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-storage $(TARGET_DIR)/usr/sbin/shareos-storage
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/S12ubus $(TARGET_DIR)/etc/init.d/S12ubus
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/S13rpcd $(TARGET_DIR)/etc/init.d/S13rpcd
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/S50uhttpd $(TARGET_DIR)/etc/init.d/S50uhttpd
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-update $(TARGET_DIR)/usr/sbin/shareos-update
	$(INSTALL) -D -m 0644 $(@D)/usr/share/rpcd/ucode/shareos.uc $(TARGET_DIR)/usr/share/rpcd/ucode/shareos.uc
	$(INSTALL) -D -m 0644 $(@D)/usr/share/rpcd/acl.d/shareos.json $(TARGET_DIR)/usr/share/rpcd/acl.d/shareos.json
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-uhttpd $(TARGET_DIR)/usr/sbin/shareos-uhttpd
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-cert $(TARGET_DIR)/usr/sbin/shareos-cert
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-altf $(TARGET_DIR)/usr/sbin/shareos-altf
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-factory-reset $(TARGET_DIR)/usr/sbin/shareos-factory-reset
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-net $(TARGET_DIR)/usr/sbin/shareos-net
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/S40network $(TARGET_DIR)/etc/init.d/S40network
	$(INSTALL) -D -m 0644 $(@D)/etc/config/network $(TARGET_DIR)/etc/config/network
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/rcS $(TARGET_DIR)/etc/init.d/rcS
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-users $(TARGET_DIR)/usr/sbin/shareos-users
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-shares $(TARGET_DIR)/usr/sbin/shareos-shares
	$(INSTALL) -D -m 0755 $(@D)/usr/sbin/shareos-quota $(TARGET_DIR)/usr/sbin/shareos-quota
	$(INSTALL) -D -m 0755 $(@D)/etc/init.d/S70shares $(TARGET_DIR)/etc/init.d/S70shares
	$(INSTALL) -D -m 0644 $(@D)/etc/config/accounts $(TARGET_DIR)/etc/config/accounts
	$(INSTALL) -D -m 0644 $(@D)/etc/config/shares $(TARGET_DIR)/etc/config/shares
	rm -rf $(TARGET_DIR)/www
	cp -a $(@D)/www $(TARGET_DIR)/www
endef

$(eval $(generic-package))
