################################################################################
#
# libtasn1
#
################################################################################

LIBTASN1_VERSION = 4.18.0
LIBTASN1_SITE = $(BR2_GNU_MIRROR)/libtasn1
LIBTASN1_DEPENDENCIES = bison-host host-pkgconfig

LIBTASN1_LIBTOOL_PATCH = NO
LIBTASN1_INSTALL_STAGING = YES

# We're patching fuzz/Makefile.am
#LIBTASN1_AUTORECONF = YES

# 'missing' fallback logic botched so disable it completely
LIBTASN1_CONF_ENV = MAKEINFO="true" CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include -std=gnu99"

LIBTASN1_CONF_OPT = --disable-doc --disable-static --disable-valgrind-tests

LIBTASN1_PROGS = asn1Coding asn1Decoding asn1Parser

$(eval $(call AUTOTARGETS,package,libtasn1))

$(LIBTASN1_HOOK_POST_CONFIGURE):
	$(SED) '/^SUBDIRS/s/tests//' $(@D)/Makefile
	touch $@

# We only need the library
$(LIBTASN1_HOOK_POST_INSTALL):
	$(RM) $(addprefix $(TARGET_DIR)/usr/bin/,$(LIBTASN1_PROGS))
	$(RM) $(addprefix $(STAGING_DIR)/usr/bin/,$(LIBTASN1_PROGS))
	touch $@


