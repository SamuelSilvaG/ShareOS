#############################################################
#
# nmap
#
#############################################################

#NMAP_VERSION:=5.51
#NMAP_SITE:=http://nmap.org/dist-old

NMAP_VERSION:=7.70
NMAP_SITE:=http://nmap.org/dist

#NMAP_VERSION:=7.91
#NMAP_SITE:=http://nmap.org/dist

NMAP_SOURCE:=nmap-$(NMAP_VERSION).tar.bz2

NMAP_DIR:=$(BUILD_DIR)/nmap-$(NMAP_VERSION)
NMAP_INSTALL_STAGING = NO
NMAP_LIBTOOL_PATCH = NO

NMAP_CONF_OPT = --with-libpcap=included --with-pcap=linux \
	--without-liblua --without-zenmap --without-ndiff
NMAP_CONF_ENV = ac_cv_linux_vers=$(BR2_DEFAULT_KERNEL_HEADERS)

# ifeq ($(BR2_PACKAGE_OPENSSL_COMPAT),y)
# NMAP_DEPENDENCIES += openssl-compat
# NMAP_CONF_OPT += -with-ssl=$(STAGING_DIR)/compat/usr
# NMAP_CONF_ENV += CFLAGS="-I$(STAGING_DIR)/compat/usr/include $(TARGET_CFLAGS)" \
# 	CXXFLAGS="-I$(STAGING_DIR)/compat/usr/include $(TARGET_CXXFLAGS)" \
# 	LDFLAGS="-L$(STAGING_DIR)/compat/usr/lib $(TARGET_LDFLAGS)"
# endif

$(eval $(call AUTOTARGETS,package,nmap))

$(NMAP_TARGET_INSTALL_TARGET):
	$(call MESSAGE,"Installing to target")
	$(MAKE1) DESTDIR=$(TARGET_DIR) -C $(NMAP_DIR) install
	touch $@
