################################################################################
#
# shareos-adguardhome – AdGuard Home (DNS filter) for the system app
# "dnsfilter": the official static build for ARMv5, not compiled here
#
################################################################################

SHAREOS_ADGUARDHOME_VERSION = 0.107.80
SHAREOS_ADGUARDHOME_SITE = https://github.com/AdguardTeam/AdGuardHome/releases/download/v$(SHAREOS_ADGUARDHOME_VERSION)
SHAREOS_ADGUARDHOME_SOURCE = AdGuardHome_linux_armv5.tar.gz
# the archive starts with "./AdGuardHome/"
SHAREOS_ADGUARDHOME_STRIP_COMPONENTS = 2
SHAREOS_ADGUARDHOME_LICENSE = GPL-3.0
SHAREOS_ADGUARDHOME_LICENSE_FILES = LICENSE.txt

define SHAREOS_ADGUARDHOME_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/AdGuardHome $(TARGET_DIR)/usr/bin/AdGuardHome
endef

$(eval $(generic-package))
