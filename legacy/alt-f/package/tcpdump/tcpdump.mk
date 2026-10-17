#############################################################
#
# tcpdump
#
#############################################################
# Copyright (C) 2001-2003 by Erik Andersen <andersen@codepoet.org>
# Copyright (C) 2002 by Tim Riker <Tim@Rikers.org>

TCPDUMP_VERSION:=4.9.3
#TCPDUMP_DIR:=$(BUILD_DIR)/tcpdump-$(TCPDUMP_VERSION)
TCPDUMP_SITE:=http://www.tcpdump.org/release
TCPDUMP_SOURCE:=tcpdump-$(TCPDUMP_VERSION).tar.gz

#TCPDUMP_CAT:=$(ZCAT)
TCPDUMP_DEPENDENCIES = uclibc zlib libpcap

ifneq ($(BR2_PACKAGE_TCPDUMP_SMB),y)
TCPDUMP_CONF_OPT += --disable-smb
else
TCPDUMP_CONF_OPT += --enable-smb
endif

TCPDUMP_INSTALL_TARGET_OPT = DESTDIR=$(TARGET_DIR) install

$(eval $(call AUTOTARGETS,package,tcpdump))

$(TCPDUMP_HOOK_POST_INSTALL):
	rm -f $(TARGET_DIR)/usr/sbin/tcpdump.4.9.3
	touch $@
	
# $(DL_DIR)/$(TCPDUMP_SOURCE):
# 	 $(call DOWNLOAD,$(TCPDUMP_SITE),$(TCPDUMP_SOURCE))
# 
# tcpdump-source: $(DL_DIR)/$(TCPDUMP_SOURCE)
# 
# $(TCPDUMP_DIR)/.unpacked: $(DL_DIR)/$(TCPDUMP_SOURCE)
# 	$(TCPDUMP_CAT) $(DL_DIR)/$(TCPDUMP_SOURCE) | tar -C $(BUILD_DIR) $(TAR_OPTIONS) -
# 	toolchain/patch-kernel.sh $(TCPDUMP_DIR) package/tcpdump tcpdump\*.patch
# 	$(CONFIG_UPDATE) $(TCPDUMP_DIR)
# 	touch $@

# # BUILD_CC=$(TARGET_CC) HOSTCC="$(HOSTCC)" 
# $(TCPDUMP_DIR)/.configured: $(TCPDUMP_DIR)/.unpacked
# 	(cd $(TCPDUMP_DIR); rm -f config.cache; \
# 		ac_cv_linux_vers=$(BR2_DEFAULT_KERNEL_HEADERS) \
# 		td_cv_buggygetaddrinfo=no \
# 		$(TARGET_CONFIGURE_OPTS) \
# 		$(TARGET_CONFIGURE_ARGS) \
# 		./configure \
# 		--target=$(GNU_TARGET_NAME) \
# 		--host=$(GNU_TARGET_NAME) \
# 		--build=$(GNU_HOST_NAME) \
# 		--prefix=/usr \
# 		--mandir=/usr/share/man \
# 		--infodir=/usr/share/info \
# 		$(TCPDUMP_ENABLE_SMB) \
# 		$(DISABLE_IPV6) \
# 	)
# 	$(SED) '/HAVE_PCAP_DEBUG/d' $(TCPDUMP_DIR)/config.h
# 	touch $@

#		--without-crypto \
#  CC="$(TARGET_CC)" \
# 		LDFLAGS="-L$(STAGING_DIR)/usr/lib" \
# 		LIBS="-lpcap -lcrypto" \
# 		INCLS="-I. -I$(STAGING_DIR)/usr/include" \
		
# $(TCPDUMP_DIR)/tcpdump: $(TCPDUMP_DIR)/.configured
# 	$(MAKE) -C $(TCPDUMP_DIR)
# 
# $(TARGET_DIR)/usr/sbin/tcpdump: $(TCPDUMP_DIR)/tcpdump
# 	cp -f $< $@
# 	$(STRIPCMD) $@
# 
# tcpdump-configure: $(TCPDUMP_DIR)/.configured
# 
# tcpdump-build: $(TCPDUMP_DIR)/tcpdump
# 
# tcpdump: uclibc zlib libpcap $(TARGET_DIR)/usr/sbin/tcpdump
# 
# tcpdump-clean:
# 	rm -f $(TARGET_DIR)/usr/sbin/tcpdump
# 	-$(MAKE) -C $(TCPDUMP_DIR) clean
# 
# tcpdump-dirclean:
# 	rm -rf $(TCPDUMP_DIR)
#############################################################
#
# Toplevel Makefile options
#
#############################################################
# ifeq ($(BR2_PACKAGE_TCPDUMP),y)
# TARGETS+=tcpdump
# endif
