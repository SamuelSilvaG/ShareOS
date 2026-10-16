#############################################################
#
# dev-headers-bundle
#
############################################################

DEV_HEADERS_BUNDLE_VERSION = 0.1
DEV_HEADERS_BUNDLE_SOURCE = dev-headers-bundle-$(DEV_HEADERS_BUNDLE_VERSION)

DEV_HEADERS_BUNDLE_DEPS = acl alsa-lib apr apr-util attr avahi bcrypt btrfs-progs bzip2 cffi cheetah cryptography cryptopp cryptsetup cups db dbus dosfstools duplicity e2fsprogs expat faad2 ffmpeg ffmpegthumbnailer file flac forked-daapd fuppes gdbm gettext hplip icu ipkg iptables jpeg lame libantlr libavl libconfuse libcurl libdaemon libdlna libevent2 libexif libffi libfuse libgcrypt libgd libglib2 libgpg-error libiconv libid3tag libmad libmcrypt libnl libogg libpar2 libpcap libpng librsync libsigcpp libsodium libtheora libunistring libupnp libusb libvorbis libxml2 libxslt lighttpd logitechmediaserver lxml lzo mpg123 mxml mysql ncurses neon netatalk netsnmp ntfs-3g nuts openssl p7zip pcre perl php popt pppd pptpd procps-ng pycrypto pycurl pynacl python readline sabyenc samba sane slang sox sqlite svn taglib tiff twolame wavpack wxwidgets xz yenc zlib 

# foo, foo-source, foo-patch, foo-configure, foo-build, foo-install,
# foo-install-target, foo-install-staging, foo-uninstall, foo-clean,
# foo-dirclean

# update the package file list in the shell: all files in $STAGING that are not in dev-bundle
#
# (cd $STAGING; find ./usr/include -type f)  > po
# for i in $(cat po); do if ! grep -q $i ipkgfiles/dev-bundle.lst ; then echo $i; fi; done | sort > ipkgfiles/dev-headers-bundle.lst

# /usr/bin/curl-config      /usr/bin/pcre-config      /usr/bin/xslt-config
# /usr/bin/net-snmp-config  /usr/bin/xml2-config

dev-headers-bundle: $(DEV_HEADERS_BUNDLE_DEPS)
	echo making dev-headers-bundle
	cpio -D $(STAGING_DIR) -pdu $(TARGET_DIR) < ipkgfiles/dev-headers-bundle.lst
	# copy $STAGING/usr/bin/*-config also, adjusting paths
