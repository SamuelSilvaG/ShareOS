#############################################################
#
# liberation
#
#############################################################
LIBERATION_VERSION = 2.1.5
#LIBERATION_SITE = http://www.fedorahosted.org/releases/l/i/liberation-fonts
LIBERATION_SITE = https://github.com/liberationfonts/liberation-fonts/files/7261482
LIBERATION_SOURCE = liberation-fonts-ttf-$(LIBERATION_VERSION).tar.gz
#LIBERATION_DIR = $(BUILD_DIR)/liberation-fonts-$(LIBERATION_VERSION)
#LIBERATION_CAT:=$(ZCAT)
LIBERATION_TARGET_DIR:=$(TARGET_DIR)/usr/share/fonts/liberation

LIBERATION_DEPENDENCIES = uclibc fontconfig
LIBERATION_LIBTOOL_PATCH = NO

$(eval $(call AUTOTARGETS,package,liberation))

$(LIBERATION_TARGET_BUILD) $(LIBERATION_TARGET_CONFIGURE):
	touch $@
	
$(LIBERATION_TARGET_INSTALL_TARGET):
	mkdir -p $(LIBERATION_TARGET_DIR)
	cp -a $(LIBERATION_DIR)/* $(LIBERATION_TARGET_DIR)
	touch $@

#FOO_TARGET_PATCH, FOO_TARGET_EXTRACT, FOO_TARGET_SOURCE
# FOO_TARGET_UNINSTALL, FOO_TARGET_CLEAN, FOO_TARGET_DIRCLEAN
#
# E.g. if your package has a no <configure> script you can place the following
# in your package makefile:
#
# | $(FOO_TARGET_INSTALL):
# |	touch $@

# $(DL_DIR)/$(LIBERATION_SOURCE):
# 	$(call DOWNLOAD,$(LIBERATION_SITE),$(LIBERATION_SOURCE))
# 
# liberation-source: $(DL_DIR)/$(LIBERATION_SOURCE)
# 
# $(LIBERATION_DIR)/.unpacked: $(DL_DIR)/$(LIBERATION_SOURCE)
# 	$(LIBERATION_CAT) $(DL_DIR)/$(LIBERATION_SOURCE) | tar -C $(BUILD_DIR) $(TAR_OPTIONS) -
# 	touch $@
# 
# $(LIBERATION_TARGET_DIR)/LiberationMono-Bold.ttf: $(LIBERATION_DIR)/.unpacked
# 	mkdir -p $(LIBERATION_TARGET_DIR)
# 	$(INSTALL) -m0644 $(LIBERATION_DIR)/*.ttf $(LIBERATION_TARGET_DIR)
# 	touch -c $@
# 
# liberation: uclibc $(LIBERATION_TARGET_DIR)/LiberationMono-Bold.ttf
# 
# liberation-clean:
# 	rm -rf $(LIBERATION_TARGET_DIR)
# 
# liberation-dirclean:
# 	rm -rf $(LIBERATION_DIR)
# 
# #############################################################
# #
# # Toplevel Makefile options
# #
# #############################################################
# ifeq ($(BR2_PACKAGE_LIBERATION),y)
# TARGETS+=liberation
# endif
