################################################################################
#
# nettle
#
################################################################################

NETTLE_VERSION = 3.7.3
NETTLE_SITE = http://www.lysator.liu.se/~nisse/archive
NETTLE_SOURCE = nettle-$(NETTLE_VERSION).tar.gz

#NETTLE_DEPENDENCIES = --enable-mini-gmp replaces needing libgmp
NETTLE_INSTALL_STAGING = YES

# don't include openssl support for (unused) examples as it has problems
# with static linking
NETTLE_CONF_OPT = --disable-openssl --disable-assembler --disable-arm-neon --enable-mini-gmp
NETTLE_INSTALL_TARGET_OPT = DESTDIR=$(TARGET_DIR) install

$(eval $(call AUTOTARGETS,package,nettle))

$(NETTLE_HOOK_POST_CONFIGURE):
	$(SED) '/^SUBDIRS/s/testsuite examples//' $(@D)/Makefile
	touch $@
