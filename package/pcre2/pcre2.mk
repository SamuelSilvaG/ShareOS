#############################################################
#
# PCRE
#
#############################################################

PCRE2_VERSION = 10.39
PCRE2_SOURCE = pcre2-$(PCRE2_VERSION).tar.bz2
PCRE2_SITE=https://github.com/PhilipHazel/pcre2/releases/download/pcre2-10.39
PCRE2_INSTALL_STAGING = YES
PCRE2_INSTALL_TARGET = YES
PCRE2_LIBTOOL_PATCH = NO
PCRE2_CONF_OPT = --enable-utf8

ifneq ($(BR2_INSTALL_LIBSTDCPP),y)
# pcre will use the host g++ if a cross version isn't available
PCRE2_CONF_OPT += --disable-cpp
endif

PCRE2_DEPENDENCIES = uclibc

$(eval $(call AUTOTARGETS,package,pcre2))

$(PCRE2_HOOK_POST_INSTALL): $(PCRE2_TARGET_INSTALL_TARGET)
	$(SED) 's,^prefix=.*,prefix=$(STAGING_DIR)/usr,' \
		-e 's,^exec_prefix=.*,exec_prefix=$(STAGING_DIR)/usr,' \
		-e 's,-L/usr/lib$libR,,' \
		$(STAGING_DIR)/usr/bin/pcre2-config
	rm -rf $(TARGET_DIR)/usr/share/doc/pcre
	touch $@
