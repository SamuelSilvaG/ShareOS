################################################################################
#
# rpcd
#
################################################################################

RPCD_VERSION = 69b62b1990bc0257bd01342ea1710375fa0cce6d
RPCD_SITE = https://github.com/openwrt/rpcd
RPCD_SITE_METHOD = git
RPCD_LICENSE = ISC
RPCD_DEPENDENCIES = json-c libubox ubus uci ucode
RPCD_CONF_OPTS = \
	-DFILE_SUPPORT=ON -DRPCSYS_SUPPORT=ON -DUCODE_SUPPORT=ON \
	-DIWINFO_SUPPORT=OFF

# lets anonymous clients call session.login (and nothing else)
define RPCD_INSTALL_ACL
	$(INSTALL) -D -m 0644 $(@D)/unauthenticated.json \
		$(TARGET_DIR)/usr/share/rpcd/acl.d/unauthenticated.json
endef
RPCD_POST_INSTALL_TARGET_HOOKS += RPCD_INSTALL_ACL

$(eval $(cmake-package))
