#!/bin/sh

usage() {
	echo "Usage: ShareOS.sh	
		-i <mountpoint> (install in mountpoint) |
		-m (mount the ShareOS union branch) |
		-u (umount the ShareOS union branch) |
		-s (status) |
		-n (remount with notify) |
		-r (remount with reval) |
		-l (list branches)"
	exit 1
}

install() {
	local mp
	mp="$1"
	if ! mountpoint -q "$mp"; then
		echo "$mp is not a mountpoint, exiting"
		exit 1
	fi

	echo "Installing ShareOS in $mp"
	if test -d $mp/ShareOS; then
		rm -f $mp/ShareOS/ShareOS $mp/ShareOS/ffp $mp/ShareOS/home
	else
		mkdir $mp/ShareOS
		echo "DON'T ADD, REMOVE OR MODIFY ANY FILE UNDER /ShareOS or $(realpath /ShareOS 2> /dev/null)
OR ANY OF ITS SUB-DIRECTORIES, OR THE SYSTEM MIGHT HANG!" > $mp/ShareOS/README.txt
	fi

	rm -f /ShareOS
	ln -s $mp/ShareOS /ShareOS
	
	mkdir -p /ShareOS/var/lib /ShareOS/etc/init.d
	for i in nfs misc; do
		cp -a /var/lib/$i /ShareOS/var/lib 2> /dev/null 
	done
	
	loadsave_settings -ta
	mount -t aufs -o remount,prepend:$mp/ShareOS=rw /
	return $?
}

isaufs() {
	if grep -q $1 /sys/fs/aufs/*/br* 2>/dev/null; then
		return 0
	fi
	return 1
}

support() {
	if test -z "$(grep aufs /proc/filesystems)"; then
		echo "The kernel does not supports aufs, exiting."
		exit 1;
	fi

	if test -z "$(mount -t aufs)"; then
		echo "aufs does not seems to be in use, exiting."
		exit 1;
	fi
}

check() {
	support

	if ! test -e /ShareOS -a -h /ShareOS; then
		echo "/ShareOS does not exist or is not a symbolic link, exiting. "
		exit 1
	fi

	if ! mp=$(readlink -f /ShareOS); then
		echo "/ShareOS seems to point to nowhere, exiting. "
		exit 1
	fi

	if ! mountpoint -q $(dirname $mp); then
		echo "/ShareOS is not in a mountpoint, exiting."
		exit 1
	fi
}

# When ShareOS runs without packages installed, all changes to /var/spool or var/lib will
# be lost on poweroff/reboot.
# when ShareOS packages are installed on ShareOS, that directory is used as the real /var/lib
# or /var/spool, so they persist across reboots. However, as one don't know if the /ShareOS
# directory will ever appears, the system has to start anyway; when the directory appears,
# a copy operation is performed.
#
# the directory copy operations after/before mount/umounting are prone to race conditions,
# as other programs or scripts might be changing them, but can't devise any general type
# of lock to prevent that to happens.
# This occurs frequently at boot time, when hotplugging detects the ShareOS directory and
# "rcall start" is being executed. A "can't stat <file>: No such file or directory" appears.
#
# affected ShareOS directories on the base firmware:
# /var/lib/nfs (rcnfs)
# /var/spool/atjobs /var/spool/atspool (rcat)
# /var/spool/cron (rccron)
# /var/spool/lpd /var/spool/samba

# lock file for initscripts (rcS) synchronization
aufslock=/tmp/.aufs-lock
dolock() {
	i=240
	logger -t aufs "waiting for lock"
	while ! mkdir $aufslock >& /dev/null; do
		if test $i = 0; then
			logger -t aufs "Couldn't get lock, exiting."
			exit 1
		fi
		usleep 500000
		i=$((--i))
	done
	logger -t aufs "got lock"
}

# remove aufs lock upon termination
cleanlock() {
	logger -t aufs "remove lock"
	rmdir $aufslock
}

case $1 in
	-i)
		support

		if isaufs ShareOS; then
			echo "/ShareOS already exists."
			exit 1

		elif test $# != 2; then
			echo "You must supply a mountpoint."
			exit 1

		else
			install $2
			exit $?
		fi
		;;

	-m)
		check
		if isaufs $mp; then
			echo "$mp is already a aufs branch."
			exit 0
		fi

		dolock
		trap cleanlock exit 

		mkdir -p /ShareOS/var/lib /ShareOS/etc/init.d

		#cp -a /var/lib/misc /ShareOS/var/lib 
		if ! grep -q 'DELAY_NFS=y' /etc/misc.conf; then
			cp -a /var/lib/nfs /ShareOS/var/lib 2> /dev/null
		fi

		loadsave_settings -ta
		mount -t aufs -o remount,prepend:${mp}=rw /
		exit $?
		;;

	-u)
		check
		if ! isaufs $mp; then
			echo "$mp is not a aufs branch."
			exit 1
		fi
		if ! mount -t aufs -o remount,del:$mp / ; then
			echo "Unmounting $mp aufs branch failed, stop all services first."
			exit 1
		fi

		dolock
		trap cleanlock exit

		loadsave_settings -fa
		#mkdir -p /tmp/lib /tmp/spool
		mkdir -p /tmp/lib
		for i in nfs; do
			cp -a /ShareOS/var/lib/$i /tmp/lib/ 2> /dev/null
		done

		ln -sf /tmp/lib /var/lib
		;;

	-s)
		check
		if ! isaufs $mp; then
			echo "$mp is not an aufs branch."
			exit 1
		fi
		echo "OK"
		exit 0
		;;

	-n)
# 		check
# 		if ! isaufs $mp; then
# 			echo "$mp is not a aufs branch."
# 			exit 1
# 		fi
		support
		mount -t aufs -o remount,udba=notify /
		exit $?
		;;

	-r)
# 		check
# 		if ! isaufs $mp; then
# 			echo "$mp is not a aufs branch."
# 			exit 1
# 		fi
		support
		mount -t aufs -o remount,udba=reval /
		exit $?
		;;

	-l)
		mount -t aufs
		cat /sys/fs/aufs/*/br?
		;;

	*)
		usage
		;;
esac

