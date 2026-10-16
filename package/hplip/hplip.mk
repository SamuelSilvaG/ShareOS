#############################################################
#
# hplip
#
############################################################

##########################################
#
# foomatic-db has to be build before hplip
#
##########################################

#HPLIP_VERSION = 3.12.9
#HPLIP_VERSION = 3.17.10
#HPLIP_VERSION = 3.20.9
HPLIP_VERSION = 3.22.6
HPLIP_SOURCE = hplip-$(HPLIP_VERSION).tar.gz
HPLIP_SITE = $(BR2_SOURCEFORGE_MIRROR)/project/hplip/hplip/$(HPLIP_VERSION)

#HPLIP_AUTORECONF = NO
HPLIP_AUTORECONF = NO
HPLIP_LIBTOOL_PATCH = NO
HPLIP_INSTALL_STAGING = NO
HPLIP_INSTALL_TARGET = YES

HPLIP_DEPENDENCIES = uclibc gs jpeg tiff libpng avahi cups libusb1 netsnmp sane foomatic-db

#HPLIP_CONF_ENV = CFLAGS="-I$(STAGING_DIR)/compat/usr/include $(TARGET_CFLAGS)" \
	LDFLAGS="-L$(STAGING_DIR)/compat/usr/lib $(TARGET_LDFLAGS)"

#-I$(STAGING_DIR)/usr/include/libusb-1.0/include \
	
HPLIP_CONF_ENV = DBUS_CFLAGS="-I/$(STAGING_DIR)/usr/include/dbus-1.0 \
	-I$(STAGING_DIR)/usr/lib/dbus-1.0/include"

#--enable-libusb01_build 	
HPLIP_CONF_OPT = --disable-doc-build --disable-qt3 --disable-qt4 \
	--disable-fax-build disable-gui-build --disable-dbus-build \
	--disable-imageProcessor-build \
	--enable-new-hpcups --enable-lite-build --enable-network-build \
	--enable-scan-build --enable-cups-ppd-install \
	--enable-hpcups-install 

$(eval $(call AUTOTARGETS,package,hplip))

$(HPLIP_HOOK_POST_EXTRACT):
	sed -i 's/DISBALE_/DISABLE_/g' $(HPLIP_DIR)/configure
	sed -i -e 's/-lImageProcessor//g' -e 's|-I/usr/include|-I/$(STAGING_DIR)/usr/include|g' -e 's|-L/usr/lib|-L/$(STAGING_DIR)/usr/lib|g' $(HPLIP_DIR)/Makefile.am
	sed -i -e 's/-lImageProcessor//g'  -e 's|-I/usr/include|-I/$(STAGING_DIR)/usr/include|g' -e 's|-L/usr/lib|-L/$(STAGING_DIR)/usr/lib|g' $(HPLIP_DIR)/Makefile.in
	touch $@
	
#$(HPLIP_HOOK_POST_CONFIGURE):
#	sed -i -e 's/chgrp/echo/' -e 's/-lImageProcessor//' $(HPLIP_DIR)/Makefile
#	touch $@

$(HPLIP_HOOK_POST_INSTALL):
	rm -rf $(TARGET_DIR)/usr/share/hal \
		$(TARGET_DIR)/etc/udev \
		$(TARGET_DIR)/usr/lib/systemd \
		$(TARGET_DIR)/var/lib/hp \
		$(TARGET_DIR)/etc/cron.daily
	touch $@
