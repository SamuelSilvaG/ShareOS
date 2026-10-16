#############################################################
#
# hdparm
#
#############################################################

HDPARM_VERSION:=9.58
HDPARM_SOURCE:=hdparm-$(HDPARM_VERSION).tar.gz
HDPARM_SITE:=$(BR2_SOURCEFORGE_MIRROR)/project/hdparm/hdparm

HDPARM_MAKE_OPT = CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)"

$(eval $(call AUTOTARGETS,package,hdparm))

$(HDPARM_TARGET_CONFIGURE):
	touch $@

$(HDPARM_TARGET_INSTALL_TARGET):
	# busybox hdparm is installed at /sbin/, use update-alternatives at pkg install time
	$(INSTALL) -m 755 $(HDPARM_DIR)/hdparm $(TARGET_DIR)/usr/sbin/hdparm
	touch $@
	
