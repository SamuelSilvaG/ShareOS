#############################################################
#
# openssl
#
############################################################

OPENSSL_VERSION:=1.1.1w
OPENSSL_SITE:=https://www.openssl.org/source

# FIXME: is MAKE1 still needed on 1.1.1?
OPENSSL_MAKE = $(MAKE)

# Some architectures are optimized in OpenSSL
OPENSSL_TARGET_ARCH=generic32
ifeq ($(ARCH),avr32)
OPENSSL_TARGET_ARCH=avr32
endif
ifeq ($(ARCH),ia64)
OPENSSL_TARGET_ARCH=ia64
endif
ifeq ($(ARCH),powerpc)
OPENSSL_TARGET_ARCH=ppc
endif
ifeq ($(ARCH),x86_64)
OPENSSL_TARGET_ARCH=x86_64
endif

OPENSSL_INSTALL_STAGING = YES
OPENSSL_INSTALL_STAGING_OPT = DESTDIR=$(STAGING_DIR) install_sw install_ssldirs
OPENSSL_INSTALL_TARGET_OPT = DESTDIR=$(TARGET_DIR) install_sw install_ssldirs
OPENSSL_HOST_INSTALL_OPT = install_sw install_ssldirs

OPENSSL_DEPENDENCIES = zlib openssl-host cryptodev
OPENSSL_CONF_OPT = -DOPENSSL_SMALL_FOOTPRINT

ifeq ($(BR2_PACKAGE_CRYPTODEV),y)
	OPENSSL_DEPENDENCIES += cryptodev
endif

OPENSSL_CFLAGS = $(TARGET_OPTIMIZATION) $(OPENSSL_CONF_OPT) $(BR2_PACKAGE_OPENSSL_OPTIM)

$(eval $(call AUTOTARGETS,package,openssl))

$(eval $(call AUTOTARGETS_HOST,package,openssl))

# load cryptodev.ko marvell_cesa.ko
# 
# / # openssl engine devcrypto
# (devcrypto) devcrypto engine
# 
# /# openssl speed -evp aes-128-cbc
# type              16 bytes     64 bytes     256 bytes    1024 bytes   8192 bytes
# aes-128-cbc       3462.90k     4104.75k     4306.43k     4356.28k     4205.59k (no mv_cesa)
# aes-128-cbc       3675.66k    14573.71k    43141.69k   286182.40k     375778.74k (mv_cesa)
# 
# / # openssl speed -evp sha1
# sha1               575.41k     1823.25k     4580.09k     7323.65k     8909.83k (no mv_cesa)
# sha1               541.06k     1754.84k     4469.86k     7254.65k     8866.47k (mv_cesa)

#			--libdir=lib \
			
$(OPENSSL_HOST_CONFIGURE):
	(cd $(OPENSSL_HOST_DIR); \
		LDFLAGS=-L$(HOST_DIR)/usr/lib ./config \
			--prefix=$(HOST_DIR)/usr \
			--openssldir=$(HOST_DIR)/usr/etc/ssl \
			threads no-shared zlib-dynamic; \
		$(MAKE) depend \
	)
	touch $@

# see also https://wiki.openssl.org/index.php/Compilation_and_Installation
# possible enable/disable openssl capabilities:
# grep -r '^#if.*OPENSSL_NO' . | grep -o 'OPENSSL_NO_[a-zA-Z0-9_]*' | sort -u | sed 's/OPENSSL_//' | tr '[A-Z_]' '[a-z-]'
# gives: no-afalgeng no-algorithms no-aria no-asan no-asm no-async no-autoalginit no-autoerrinit no-autoload-config no-bf no-blake2 no-camellia no-capieng no-cast no-chacha no-cmac no-cms no-comp no-crypto-mdebug no-crypto-mdebug-backtrace no-ct no-decc-init no-des no-devcryptoeng no-dgram no-dh no-dsa no-dtls no-dtls1 no-dtls1-2 no-dtls1-2-method no-dtls1-method no-dynamic-engine no-ec no-ec2m no-ec-nistp-64-gcc-128 no-egd no-engine no-err no-external-tests no-fuzz-afl no-fuzz-libfuzzer no-gost no-heartbeats no-hw no-hw-padlock no-idea no-inline-asm no-md2 no-md4 no-md5 no-mdc2 no-msan no-multiblock no-nextprotoneg no-ocb no-ocsp no-poly1305 no-posix-io no-psk no-rc2 no-rc4 no-rc5 no-rfc3779 no-rmd160 no-rsa no-scrypt no-sctp no-seed no-siphash no-sm2 no-sm3 no-sm4 no-sock no-srp no-srtp no-ssl3 no-ssl3-method no-ssl-trace no-static-engine no-stdio no-tests no-tls no-tls1 no-tls1-1 no-tls1-1-method no-tls1-2 no-tls1-2-method no-tls1-3 no-tls1-method no-ts no-ubsan no-ui-console no-unit-test no-weak-ssl-ciphers no-whirlpool
	
$(OPENSSL_TARGET_CONFIGURE):
	(cd $(OPENSSL_DIR); \
		$(TARGET_CONFIGURE_ARGS) \
		$(TARGET_CONFIGURE_OPTS) \
		./Configure \
			--prefix=/usr \
			--openssldir=/etc/ssl \
			$(OPENSSL_CONF_OPT) \
			linux-$(OPENSSL_TARGET_ARCH) \
			shared threads no-async \
			enable-devcryptoeng no-afalgeng no-capieng no-hw-padlock no-egd \
			no-tests no-fuzz-libfuzzer no-fuzz-afl \
			enable-deprecated no-autoerrinit no-sse2 no-gost no-srp \
			no-sm2 no-sm3 no-sm4 \
			no-idea no-md2 no-mdc2 no-rc5 no-camellia no-aria no-whirlpool \
			no-seed no-err no-comp \
			no-dtls no-dtls1-method no-dtls1_2-method \
			no-tls1 no-tls1-method no-tls1_1 no-tls1_1-method \
			no-ssl3 no-ssl3-method \
	)
	# marvell_cesa and cryptodev-linux: enable-engine enable-dso enable-devcryptoeng
	# no-engine no-dynamic-engine # no-ct no-ocsp
	# look at no-dtls (TLS over UDP)
	$(SED) "s/build_tests //" $(OPENSSL_DIR)/Makefile
	touch $@

$(OPENSSL_TARGET_BUILD):
	# libs compiled with chosen optimization.
	$(SED) "s:-O[s0-9]:$(OPENSSL_CFLAGS):" $(OPENSSL_DIR)/Makefile
	$(OPENSSL_MAKE) -C $(OPENSSL_DIR) depend build_libs
	# openssl program compiled with -Os, saves 27KB
	$(SED) "s:-O[s0-9]:$(BR2_PACKAGE_OPENSSL_OPTIM2):" $(OPENSSL_DIR)/Makefile
	$(OPENSSL_MAKE) -C $(OPENSSL_DIR) build_apps
	touch $@

$(OPENSSL_HOOK_POST_INSTALL):
	$(if $(BR2_HAVE_DEVFILES),,rm -rf $(TARGET_DIR)/usr/lib/ssl)
ifeq ($(BR2_PACKAGE_OPENSSL_BIN),y)
	$(STRIPCMD) $(STRIP_STRIP_ALL) $(TARGET_DIR)/usr/bin/openssl
else
	rm -f $(TARGET_DIR)/usr/bin/openssl
endif
	rm -f $(TARGET_DIR)/usr/bin/c_rehash \
		$(TARGET_DIR)/etc/ssl/openssl.cnf.dist \
		$(TARGET_DIR)/etc/ssl/ct_log_list*
	rm -rf $(TARGET_DIR)/etc/ssl/misc
	# libraries gets installed read only, so strip fails
	for i in $(addprefix $(TARGET_DIR)/usr/lib/,libcrypto.so.* libssl.so.*); \
	do chmod +w $$i; $(STRIPCMD) $(STRIP_STRIP_UNNEEDED) $$i; done
ifneq ($(BR2_PACKAGE_OPENSSL_ENGINES),y)
	rm -rf $(TARGET_DIR)/usr/lib/engines
else
	-chmod +w $(TARGET_DIR)/usr/lib/engines/lib*.so
	-$(STRIPCMD) $(STRIP_STRIP_UNNEEDED) $(TARGET_DIR)/usr/lib/engines/lib*.so
endif
	# FIXME: this takes too long, execute only if it does not exists.
	mkdir -p $(TARGET_DIR)/etc/ssl/certs
	if ! test -f $(TARGET_DIR)/etc/ssl/dhparam.pem; then \
	openssl dhparam -out $(TARGET_DIR)/etc/ssl/dhparam.pem 2048; fi
	touch $@

$(OPENSSL_TARGET_UNINSTALL):
	$(call MESSAGE,"Uninstalling")
	rm -rf $(addprefix $(TARGET_DIR)/,etc/ssl usr/bin/openssl usr/include/openssl)
	rm -rf $(addprefix $(TARGET_DIR)/usr/lib/,ssl engines libcrypto* libssl* pkgconfig/libcrypto.pc)
	rm -rf $(addprefix $(STAGING_DIR)/,etc/ssl usr/bin/openssl usr/include/openssl)
	rm -rf $(addprefix $(STAGING_DIR)/usr/lib/,ssl engines libcrypto* libssl* pkgconfig/libcrypto.pc)
	rm -f $(OPENSSL_TARGET_INSTALL_TARGET) $(OPENSSL_HOOK_POST_INSTALL)
