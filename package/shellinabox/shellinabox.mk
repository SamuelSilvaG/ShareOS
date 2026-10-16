#############################################################
#
# shellinabox
#
############################################################

#SHELLINABOX_VERSION = 2.20
#SHELLINABOX_SITE = https://github.com/shellinabox/shellinabox/archive
#SHELLINABOX_SOURCE2 = v$(SHELLINABOX_VERSION).tar.xz

SHELLINABOX_VERSION = 2.21
SHELLINABOX_SITE = https://deb.debian.org/debian/pool/main/s/shellinabox
SHELLINABOX_SOURCE = shellinabox_$(SHELLINABOX_VERSION).tar.xz

SHELLINABOX_LIBTOOL_PATCH = NO
SHELLINABOX_AUTORECONF = YES
SHELLINABOX_INSTALL_STAGING = NO

SHELLINABOX_DEPENDENCIES = openssl
SHELLINABOX_CONF_OPT = --disable-pam --disable-utmp

$(eval $(call AUTOTARGETS,package,shellinabox))

# $(SHELLINABOX_TARGET_SOURCE):
# 	$(call DOWNLOAD,$(SHELLINABOX_SITE),$(SHELLINABOX_SOURCE))
# 	(cd $(DL_DIR); ln -sf $(SHELLINABOX_SOURCE2) $(SHELLINABOX_SOURCE) )
# 	mkdir -p $(BUILD_DIR)/shellinabox-$(SHELLINABOX_VERSION)
# 	touch $@
