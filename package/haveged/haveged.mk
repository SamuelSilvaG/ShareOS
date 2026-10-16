#############################################################
#
# haveged
#
#############################################################

HAVEGED_VERSION:=1.9.18
HAVEGED_SOURCE:=v$(HAVEGED_VERSION).tar.gz
HAVEGED_SITE:=https://github.com/jirka-h/haveged/archive/refs/tags

HAVEGED_AUTORECONF:=NO
HAVEGED_INSTALL_STAGING:=NO
HAVEGED_INSTALL_TARGET:=YES
HAVEGED_LIBTOOL_PATCH:=NO

HAVEGED_CONF_OPT = --disable-shared --disable-static \
	--enable-diagnostic=no --enable-enttest=no --enable-olt=no

HAVEGED_DEPENDENCIES:=uclibc

$(eval $(call AUTOTARGETS,package,haveged))

$(HAVEGED_HOOK_POST_EXTRACT):
	$(SED) 's/-Wpedantic//' $(HAVEGED_DIR)/src/Makefile.in
	touch $@
