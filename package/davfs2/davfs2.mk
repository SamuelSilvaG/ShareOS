#############################################################
#
# davfs2
#
#############################################################

DAVFS2_VERSION = 1.6.0
DAVFS2_SITE = http://download.savannah.gnu.org/releases/davfs2
DAVFS2_SOURCE = davfs2-$(DAVFS2_VERSION).tar.gz

DAVFS2_AUTORECONF = NO
DAVFS2_LIBTOOL_PATCH = YES

DAVFS2_INSTALL_STAGING = NO
DAVFS2_INSTALL_TARGET = YES

DAVFS2_DEPENDENCIES = uclibc neon libiconv
DAVFS2_CONF_ENV = LIBS=-liconv
DAVFS2_CONF_OPT = --with-neon=$(STAGING_DIR)/usr

$(eval $(call AUTOTARGETS,package,davfs2))

$(DAVFS2_HOOK_POST_CONFIGURE):
	$(SED) '/-fstack-protector-strong/d' $(DAVFS2_DIR)/src/Makefile
	touch $@

$(DAVFS2_HOOK_POST_INSTALL):
	rm -f $(TARGET_DIR)/sbin/mount.davfs $(TARGET_DIR)/sbin/umount.davfs
	touch $@
