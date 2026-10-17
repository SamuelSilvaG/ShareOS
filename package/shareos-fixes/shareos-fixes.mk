################################################################################
#
# shareos-fixes – small adjustments to buildroot packages
#
################################################################################

# buildroot gives libcurl a default CA bundle only for OpenSSL and wolfSSL.
# With mbedTLS curl trusts no certificate at all ("not correctly signed by the
# trusted CA"), so the updater could not reach GitHub.
ifeq ($(BR2_PACKAGE_LIBCURL_MBEDTLS),y)
LIBCURL_CONF_OPTS += \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
	--with-ca-path=/etc/ssl/certs
endif
