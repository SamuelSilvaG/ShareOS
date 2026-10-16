#############################################################
#
# miniupnpc
#
#############################################################

MINIUPNPC_VERSION:=2.1.20191224
MINIUPNPC_SOURCE:=miniupnpc-$(MINIUPNPC_VERSION).tar.gz
MINIUPNPC_SITE:=http://miniupnp.free.fr/files/

MINIUPNPC_LIBTOOL_PATCH = NO

MINIUPNPC_MAKE_ENV= CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)"
MINIUPNPC_MAKE_OPT = upnpc-static listdevices

MINIUPNPC_INSTALL_TARGET_OPT = DESTDIR=$(TARGET_DIR) install-static

$(eval $(call AUTOTARGETS,package,miniupnpc))

$(MINIUPNPC_TARGET_CONFIGURE):
	touch $@

$(MINIUPNPC_TARGET_INSTALL_TARGET):
	$(INSTALL) -m 755 $(MINIUPNPC_DIR)/upnpc-static $(TARGET_DIR)/usr/bin/upnpc
	$(INSTALL) -m 755 $(MINIUPNPC_DIR)/listdevices $(TARGET_DIR)/usr/bin/listdevices
	touch $@
