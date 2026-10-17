################################################################################
#
# alt-f-utils
#
################################################################################

ALT_F_UTILS_VERSION = 0.1.11
ALT_F_UTILS_SITE = $(BR2_EXTERNAL_SHAREOS_PATH)/src/alt-f-utils
ALT_F_UTILS_SITE_METHOD = local
ALT_F_UTILS_LICENSE = GPL-2.0+
ALT_F_UTILS_LICENSE_FILES = dns323-fw.c

ALT_F_UTILS_BINS = dns320l-daemon dns323-fw
ifeq ($(BR2_PACKAGE_ALT_F_UTILS_SYSCTRL),y)
ALT_F_UTILS_BINS += sysctrl
endif

define ALT_F_UTILS_BUILD_CMDS
	$(foreach b,$(ALT_F_UTILS_BINS), \
		$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -D_GNU_SOURCE \
			-o $(@D)/$(b) $(@D)/$(b).c || exit 1;)
endef

define ALT_F_UTILS_INSTALL_TARGET_CMDS
	$(foreach b,$(ALT_F_UTILS_BINS), \
		$(INSTALL) -D -m 0755 $(@D)/$(b) $(TARGET_DIR)/usr/sbin/$(b);)
endef

define HOST_ALT_F_UTILS_BUILD_CMDS
	$(HOSTCC) $(HOST_CFLAGS) $(HOST_LDFLAGS) -D_GNU_SOURCE \
		-o $(@D)/dns323-fw $(@D)/dns323-fw.c
endef

define HOST_ALT_F_UTILS_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/dns323-fw $(HOST_DIR)/bin/dns323-fw
endef

$(eval $(generic-package))
$(eval $(host-generic-package))
