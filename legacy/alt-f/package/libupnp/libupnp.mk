#############################################################
#
# libupnp
#
#############################################################

LIBUPNP_VERSION:=1.6.6
LIBUPNP_SOURCE:=libupnp-$(LIBUPNP_VERSION).tar.bz2
LIBUPNP_SITE:=$(BR2_SOURCEFORGE_MIRROR)/project/pupnp/pupnp/libUPnP%20$(LIBUPNP_VERSION)

# inline functions do not became externaly visible with -Os,
# it might be related with -fgnu89-inline
LIBUPNP_CONF_ENV = ac_cv_lib_compat_ftime=no ac_cv_cflags_gcc_option__Os=""
LIBUPNP_CONF_OPT = --disable-static

LIBUPNP_INSTALL_STAGING:=YES

$(eval $(call AUTOTARGETS,package,libupnp))
