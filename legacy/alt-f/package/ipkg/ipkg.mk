#############################################################
#
# ipkg
#
#############################################################

IPKG_VERSION = 0.99.163
IPKG_SOURCE = ipkg-$(IPKG_VERSION).tar.gz
IPKG_SITE = https://ftp.gwdg.de/pub/linux/handhelds/packages/ipkg

IPKG_AUTORECONF = NO
IPKG_CONF_OPT = --disable-shared

IPKG_DEPENDENCIES = uclibc

$(eval $(call AUTOTARGETS,package,ipkg))
