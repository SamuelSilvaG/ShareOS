#!/bin/bash

#set -x

# recursively find packages that <package> depends on: 
rdeps() {
	pf=$1
	if test "$pf" = "kernel-modules"; then return; fi # only in sqimage, handle latter
	if ! grep -q ^BR2_PACKAGE_$(echo $pf | tr '[:lower:]-' '[:upper:]_')=y $CWD/.config; then return; fi
	
	echo $pf $(awk '/Version:/{print $2}' $CWD/ipkgfiles/$pf.control)
	deps=$(awk '/Depends:/{for (i=2; i<=NF; i++) print $i}' $CWD/ipkgfiles/$pf.control)
	for i in $deps; do
		rdeps ${i%%,}
	done
}

# preinst.status needed at runtime to avoid installing pre installed packages
# when they are dependencies of a new package being installed
deps_status() {
	grep -E '(Package:|Version:|Depends:|Architecture:|Priority:|Essential:)' $CWD/ipkgfiles/$1.control
	echo "Status: install user installed"
	echo "Installed-Time: $(date +%s)"
					
	if test -f $CWD/ipkgfiles/$1.conffiles; then
		echo Conffiles: 
		for j in $(cat $CWD/ipkgfiles/$1.conffiles); do
			echo "$j $(md5sum $BLDDIR/project_build_arm/$board/root/$j | cut -d" " -f1)"
		done
	fi  
	echo
}

deps_check() {
	pf=$1
	if test "$pf" = "kernel-modules"; then pf="$pf-$arch"; fi
	if ! ( cd $CWD; ./mkpkg.sh -check $pf >& /dev/null); then
		echo "WARNING: Package $pf does not contains all files, might or not be OK!" > $(tty)
	fi
}

beroot() {
	if test $(whoami) != "root"; then
		sudo -E $0 $TYPE $COMP
		exit $?
	fi
}

usage() {
	echo "Usage: mkinitramfs [-s (no squash)] [-u (no UBI)] [type] (cpio|squsr|sqall*|sqsplit) [compression] (gz|lzma|xz*)"
	exit 1
}

if test "$(dirname $0)" != "."; then
	echo "mkinitramfs: This script must be run in the root of the tree, exiting."
	exit 1;
fi

if test -z "$BLDDIR"; then
	echo "mkinitramfs: Run '. exports [board]' first."
	exit 1
fi

while getopts ":su" o; do
    case "${o}" in
        s) echo "-s: No SQUASH image generated"; NO_SQUASH=1 ;;
        u) echo "-u: No UBI image generated"; NO_UBI=1;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))

if test -n "$NO_UBI" -a -n "$NO_SQUASH"; then
	echo "mkinitramfs: both '-u' and '-s' specified, at least one image must be built."
	exit 1
fi

if test "$#" = 0; then
	TYPE=sqall
	COMP=xz
elif test "$#" = 1; then
	if test "$1" = "cpio" -o "$1" = "squsr" -o "$1" = "sqall" -o "$1" = "sqsplit"; then
		TYPE=$1
		COMP=xz
	elif test "$1" = "gz" -o "$1" = "lzma" -o "$1" = "xz"; then
		TYPE=sqall
		COMP=$1
	else
		usage
	fi
elif test "$#" = 2; then
	TYPE=$1
	COMP=$2
else
	usage
fi

if test $TYPE != "cpio" -a $TYPE != "squsr" -a $TYPE != "sqall" -a "$1" != "sqsplit" \
	-a $COMP != "gz" -a $COMP != "lzma" -a $COMP != "xz"; then
	usage
fi

if test -z "$ME" -o -z "$MG"; then
	export ME=$(id -un)
	export MG=$(id -gn)
fi

. .config 2> /dev/null
board=$BR2_PROJECT
kver=$BR2_CUSTOM_LINUX26_VERSION

EXT=$COMP
if test "$COMP" = "xz"; then
	cmd="xz --check=crc32 -z -6"
elif test "$COMP" = "lzma"; then
	cmd="lzma -6"
elif test "$COMP" = "gz"; then
	cmd="gzip -9"
	COMP=gzip
else
	echo "mkinitramfs: unknown compressor."
	exit 1
fi

# FIXME: shouldn't this be in .config instead? to diminish redundancy and missing dependencies?
# fw_pkgs: pre-installed packages in base firmware
# sq_pkgs: pre-installed packages on extra_image 
# base_pkgs/base_pkgs2 contains all packages for the base firmware but uClibc.
# Other packages often don't explicitly depends on them, so we have to list them all here.
base_pkgs="haveged busybox alt-f-utils mdadm e2fsprogs dosfstools gptfdisk-sgdisk sfdisk dropbear kexec wsdd2 zlib popt"
base_pkgs2="ntp-common wget openssl libiconv msmtp"

# removed from dns323 due to update to linux-4.14.188/openssl-1.1.1 and lack of flash space:
# rsync vsftpd ntfs-3g inadyn-mt cifs-utils nfs-utils smartmontools openssh-sftp stunnel at
#
# they have to be installed as disk meta-package "dns-323-321-compat"

# 535672  /usr/sbin/smartd
# 461850  cifs.ko (cifs-utils)
# 424320  /usr/sbin/smartctl
# 375256  /usr/bin/rsync
# 307540  /usr/lib/libntfs-3g.so.83.0.0 
# 158724  /usr/bin/stunnel
# 123172  /usr/bin/inadyn-mt
# 105516  /usr/sbin/vsftpd 
# 105400  /usr/bin/msmtp
# 104918  fuse.ko (ntfs-3g)
# 102432  /usr/bin/ntfs-3g
#  75588  /usr/lib/sftp-server (openssh-sftp)
#  30208  /usr/sbin/mount.cifs (cifs-utils)

# SQFSBLK: squashfs compression block sizes: 131072 262144 524288 1048576
SQFSBLK=131072

case $board in
	dns323|qemu)
		SQFSBLK=262144
		fw_pkgs="$base_pkgs $base_pkgs2 samba-small"
		all_pkgs=$fw_pkgs
		;;
	dns325|dns327)
		if test $# = 0; then
			TYPE="sqsplit"
			COMP=xz
		fi
		fw_pkgs="$base_pkgs nfs-utils portmap mtd-utils"
		sq_pkgs="$base_pkgs2 at stunnel vsftpd rsync openssh-sftp smartmontools cifs-utils ntfs-3g inadyn-mt dnsmasq msmtp libcurl quota-tools samba4 gptfdisk btrfs-progs ntfsprogs exfatprogs e2fsprogs-extra cryptsetup lvm2 minidlna transmission"
		all_pkgs="$fw_pkgs $sq_pkgs"
		;;
	*) echo "mkinitramfs: Unsupported \"$board\" board"; exit 1;;
esac

if test "$board" = "dns327"; then arch="armv7"; else arch="armv5"; fi

CWD=$PWD

# base packages /etc configuration files
base_conf=$(for i in $base_pkgs $base_pkgs2; do grep './etc/' $CWD/ipkgfiles/$i.lst; done)

# all packages (and needed dependencies) /etc configuration files
all=$(for i in $all_pkgs; do rdeps $i; done | sort -u | cut -d" " -f1)
all_conf=$(for i in $all; do grep './etc/' $CWD/ipkgfiles/$i.lst; done)

# deprecated
if test "$TYPE" = "cpio"; then # standard initramfs
	beroot

	cd ${BLDDIR}/binaries/$board
	mkdir -p tmp

	mount -o ro,loop rootfs.arm.ext2 tmp
	cd tmp
	find . | cpio --quiet -o -H newc | $cmd > ../rootfs.arm.$TYPE.$EXT
	cd ..
	umount tmp
	rmdir tmp

	chown $ME:$MG rootfs.arm.$TYPE.$EXT

# deprecated
elif test "$TYPE" = "squsr"; then # standard initramfs with /usr squashed
	beroot

	cd ${BLDDIR}/binaries/$board
	mkdir -p tmp

	cp rootfs.arm.ext2 rootfs.arm.ext2.tmp
	mount -o loop rootfs.arm.ext2.tmp tmp

	mksquashfs tmp/usr/ usr.squashfs -comp $COMP -b $SQFSBLK \
		-always-use-fragments -keep-as-directory -all-root
	rm -rf tmp/usr/*
	mv usr.squashfs tmp
	cd tmp

	find . | cpio --quiet -o -H newc | $cmd > ../rootfs.arm.$TYPE.$EXT
	cd ..
	umount tmp
	rmdir tmp
	rm rootfs.arm.ext2.tmp

	chown $ME:$MG rootfs.arm.$TYPE.$EXT

# DNS-321/323
elif test "$TYPE" = "sqall"; then # squashfs initrd, everything squashed

	cd ${BLDDIR}/project_build_arm/$board/

	fw_pkgs_deps=$(for i in $fw_pkgs; do rdeps $i; done | sort -u)

	# create ipkg status file stating which packages are pre installed
	echo "$fw_pkgs_deps" | sort -u > root/etc/preinst
	rm -f root/etc/preinst.status
	for i in $(echo "$fw_pkgs_deps" | cut -d' ' -f1); do
		deps_check $i
		deps_status $i
	done >> root/etc/preinst.status
	
	# update /etc/settings with pre installed package configuration files
	echo -e "$base_conf\n$all_conf" | sort | uniq -u | grep -vE '/etc/init.d|/etc/avahi/services' | sed 's|^./|/|' >> root/etc/settings

	# mksquashfs can create device nodes
	rm -f root/dev/null root/dev/console
	if ! test -f $CWD/mksquashfs.pf; then
		cat<<-EOF > $CWD/mksquashfs.pf
		/dev/null c 666 root root 1 3
		/dev/console c 600 root root 5 1
		EOF
	fi
	mksquashfs root rootfs.arm.$TYPE.$EXT -comp $COMP -noappend -b $SQFSBLK \
		-always-use-fragments -all-root -pf $CWD/mksquashfs.pf

	mv rootfs.arm.sqall.$EXT ${BLDDIR}/binaries/$board

# DNS-320/325/327
elif test "$TYPE" = "sqsplit"; then # as 'sqall' above but also create extra_image with extra pkgs

	if test "$board" != "dns325" -a "$board" != "dns327"; then
		echo "mkinitramfs: ERROR, \"sqsplit\" is only for a dns-320/325/327"
		exit 1
	fi

	cd ${BLDDIR}/project_build_arm/$board/

	fw_pkgs_deps=$(for i in $fw_pkgs; do rdeps $i; done | sort -u)
	# popt and msmtp/wget requires iconv and openssl, but they don't fit on the 
	# image size of a dns-320L. They are instead explicitly listed on sq_pkgs
	fw_pkgs_deps=$(echo "$fw_pkgs_deps" | grep -vE libiconv\|openssl)
	
	sq_pkgs_deps=$(for i in $sq_pkgs; do rdeps $i; done | sort -u)

	# add kernel-modules to sqimage
	sq_pkgs_deps=$(echo -e "$sq_pkgs_deps\nkernel-modules-$arch $kver")
	
	# bug 363: remove from sq_pkgs_deps any entries already in fw_pkgs_deps
	sq_pkgs_deps=$(echo -e "$fw_pkgs_deps\n$fw_pkgs_deps\n$sq_pkgs_deps" | sort | uniq -u)
	echo -e "$fw_pkgs_deps" | sort -u > $CWD/fw-pkgs
	echo -e "$sq_pkgs_deps" | sort -u > $CWD/sq-pkgs

##	echo -e "$fw_pkgs_deps\n$sq_pkgs_deps" | sort -u > root/etc/preinst
	echo -e "$fw_pkgs_deps" | sort -u > root/etc/preinst
	echo -e "$sq_pkgs_deps" | sort -u > root/etc/preinst-sq
	
	# create ipkg status file stating which packages are pre installed
	rm -f root/etc/preinst.status root/etc/preinst-sq.status
	for i in $(echo "$fw_pkgs_deps" | cut -d' ' -f1); do
		deps_check $i
		deps_status $i
	done >> root/etc/preinst.status
#	for i in $(echo "$sq_pkgs_deps" | cut -d' ' -f1); do
#		deps_check $i
#		deps_status $i
#	done >> root/etc/preinst-sq.status

	# update /etc/settings with pre installed package configuration files
	echo -e "$base_conf\n$all_conf" | sort | uniq -u | grep -vE '/etc/init.d|/etc/avahi/services' | sed 's|^./|/|' >> root/etc/settings
	
	# create extra_image pkgs file list and ipkg status file stating which packages are pre installed
	TF=$(mktemp)
	rm -rf extra_image
	mkdir -p extra_image/usr/lib/ipkg/info
	for i in $(echo "$sq_pkgs_deps" | cut -d' ' -f1); do
		deps_check $i
		deps_status $i
		cat $CWD/ipkgfiles/$i.lst >> $TF
		cp $CWD/ipkgfiles/$i.* extra_image/usr/lib/ipkg/info
##	done >> root/etc/preinst.status
	done >> extra_image/usr/lib/ipkg/status
	cp extra_image/usr/lib/ipkg/status root/etc/preinst-sq.status
	rename .lst .list extra_image/usr/lib/ipkg/info/*.lst
	rm -f extra_image/usr/lib/ipkg/info/*~
	
# FIXME: to use flash, the package info needs to be stored in flash,
# /rootmnt/ubiimage/usr/lib/ipkg/info/<pkg>.*
# and the ipkg status file in flash /rootmnt/ubiimage/usr/lib/ipkg/status contain it
#
# what about /etc/preinst and /etc/preinst.status? The webui and ipkg front end uses them.
# if removed/commented from /etc/preinst the webui allows removing it
# the ipkg-fe will restore /usr/lib/ipkg/status from /etc/preinst.status

	# extra_image files list, to be removed from base and present only on extra_image
	extra_imagefiles=$(cat $TF | sort -u)
	rm $TF

	rm -rf image
	cp -a root image
##	mkdir -p extra_image
	cd image
	# create dirs first, as packages often don't have dirs name on it
	# and its permission needs to be preserved
	find . -type d | cpio -p ../extra_image 
	echo "$extra_imagefiles" | cpio -pu ../extra_image
	rm -f $extra_imagefiles >& /dev/null
	cd ..
	# remove empty dirs on extra_image (image itself *has* to have them)
	find extra_image -depth -type d -empty -exec rmdir {} \;
	
	rm -f image/dev/null image/dev/console # mksquashfs can create device nodes
	if ! test -f $CWD/mksquashfs.pf; then
		cat<<-EOF > $CWD/mksquashfs.pf
		/dev/null c 666 root root 1 3
		/dev/console c 600 root root 5 1
		EOF
	fi
	mksquashfs image rootfs.arm.sqall.$EXT -comp $COMP -noappend -b $SQFSBLK \
		-always-use-fragments -all-root -pf $CWD/mksquashfs.pf
	mv rootfs.arm.sqall.$EXT ${BLDDIR}/binaries/$board

if test -z "$NO_SQUASH"; then
	mksquashfs extra_image rootfs.arm.sqimage.$EXT -comp $COMP -noappend \
		-b $SQFSBLK -always-use-fragments -all-root
	mv rootfs.arm.sqimage.$EXT ${BLDDIR}/binaries/$board
fi

if test -z "$NO_UBI"; then
	mkfs.ubifs -v -F -c 800 -e 126976 -m 2048 -r extra_image image.ubifs.lzo
	ubinize -o rootfs.arm.ubimage.lzo -p 131072 -m 2048 -s 2048 -O 2048 $CWD/ubi.ini
	mv rootfs.arm.ubimage.lzo ${BLDDIR}/binaries/$board
	rm image.ubifs.lzo
fi

else
	usage
fi



