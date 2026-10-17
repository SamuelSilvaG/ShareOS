#############################################################
#
# libtirpc
#
#############################################################

# patches from from the BuildRoot site
# still fails when installing to target, as it wants to strip rpcgen,
# which is in host binary, not a target binary

#LIBTIRPC_VERSION = 0.2.2
LIBTIRPC_VERSION = 1.3.2
LIBTIRPC_SITE = $(BR2_SOURCEFORGE_MIRROR)/project/libtirpc/libtirpc/$(LIBTIRPC_VERSION)
LIBTIRPC_SOURCE = libtirpc-$(LIBTIRPC_VERSION).tar.bz2

LIBTIRPC_AUTORECONF = NO
LIBTIRPC_LIBTOOL_PATCH = NO

LIBTIRPC_INSTALL_STAGING = YES
LIBTIRPC_INSTALL_TARGET = YES

LIBTIRPC_CONF_ENV = CFLAGS="$(TARGET_CFLAGS) -DGQ"
LIBTIRPC_CONF_OPT = --disable-gssapi

LIBTIRPC_DEPENDENCIES = host-pkgconfig

$(eval $(call AUTOTARGETS,package,libtirpc))
$(eval $(call AUTOTARGETS_HOST,package,libtirpc))

# $(LIBTIRPC_HOOK_POST_INSTALL):
# 	cp -a $(STAGING_DIR)/usr/include/tirpc/* $(STAGING_DIR)/usr/include/
# 	touch $(@)

$(LIBTIRPC_HOOK_POST_CONFIGURE):
	if ! test -f $(STAGING_DIR)/usr/include/err.h; then \
	(echo '#include <errno.h>'; \
	echo '#define err(exitcode, format, args...) \
		errx(exitcode, format ": %s", ## args, strerror(errno))'; \
	echo '#define errx(exitcode, format, args...) \
		{ warnx(format, ## args); exit(exitcode); }'; \
	echo '#define warn(format, args...) \
		warnx(format ": %s", ## args, strerror(errno))'; \
	echo '#define warnx(format, args...) \
		fprintf(stderr, format, ## args)'; \
	) > $(LIBTIRPC_DIR)/err.h; \
	fi
	touch $@
