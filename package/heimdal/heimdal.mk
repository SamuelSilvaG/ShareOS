################################################################################
#
# heimdal
#
################################################################################

HEIMDAL_VERSION = 7.7.0
HEIMDAL_SITE = https://github.com/heimdal/heimdal/releases/download/heimdal-$(HEIMDAL_VERSION)

HOST_HEIMDAL_DEPENDENCIES = host-e2fsprogs host-ncurses host-pkgconfig
HEIMDAL_INSTALL_STAGING = YES

# static because of -fPIC issues with e2fsprogs on x86_64 host
HEIMDAL_HOST_CONF_OPT = \
	--disable-shared \
	--enable-static \
	--without-openldap \
	--without-capng \
	--with-db-type-preference= \
	--without-sqlite3 \
	--without-libintl \
	--without-openssl \
	--without-berkeley-db \
	--without-readline \
	--without-libedit \
	--without-hesiod \
	--without-x \
	--disable-mdb-db \
	--disable-ndbm-db \
	--disable-heimdal-documentation

# Don't use compile_et from e2fsprogs as it raises a build failure with samba4
HEIMDAL_HOST_CONF_ENV = ac_cv_prog_COMPILE_ET=no MAKEINFO=true

$(eval $(call AUTOTARGETS_HOST,package,heimdal))

$(HEIMDAL_HOST_HOOK_POST_INSTALL):
	# We need compile_et for samba4
	$(INSTALL) -m 0755 $(@D)/lib/com_err/compile_et \
		$(HOST_DIR)/usr/bin/compile_et
	# We need asn1_compile in the PATH for samba4
	ln -sf $(HOST_DIR)//usr/lib/heimdal/asn1_compile \
		$(HOST_DIR)/usr/bin/asn1_compile
	touch $@

