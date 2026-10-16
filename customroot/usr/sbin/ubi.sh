#!/bin/sh

#set -x

usage() {
	echo "Usage: ubi.sh	-a (attach) |
		-d (detach) |
		-r (readonly) |
		-w (readwrite) |
		-l (list)"
}

list() {
	echo -n "UBI:  "
	mount -t ubifs
	echo -n "AUFS: "
	aufs.sh -l | grep ubiimage
}

#attach and mount RO
attach() {
	if ubiattach -d 1 -p /dev/mtd3 -O 2048; then # ubi/ubifs setup
		mkdir -p /rootmnt/ubiimage
		if mount -t ubifs -o ro /dev/ubi1_0 /rootmnt/ubiimage; then
			sync
			#mount -t aufs -o remount,append:/rootmnt/ubiimage=ro /
			# insert where /rootmnt/ro currently is; ro will be at bottom
			ix=$(basename $(grep -l /rootmnt/ro /sys/fs/aufs/*/br?))
			mount -t aufs -o remount,ins:${ix#br}:/rootmnt/ubiimage=ro /
		else
			echo "UBIimage mount failed."
			ubidetach -p /dev/mtd3
			exit 1
		fi
	else
		echo "UBIimage attach failed."
		exit 1
	fi
	echo "Attached and mounted UBIimage in RO mode."
}

#detach
detach() {
	if mount -t ubifs | grep -q /rootmnt/ubiimage; then
		if aufs.sh -l | grep -q /rootmnt/ubiimage; then
			if ! mount -t aufs -o remount,del=/rootmnt/ubiimage /; then
				echo "Can't remove UBIimage from aufs."
				exit 1
			fi
		fi
		if ! umount /rootmnt/ubiimage; then
			echo "Can't unmount UBIimage."
			exit 1
		fi
		ubidetach -p /dev/mtd3
	fi
	echo "Unmounted an detached UBIimage."
}

#read/write
rw() {
	if mount -t ubifs | grep -q /rootmnt/ubiimage; then
		mount -t ubifs -o remount,rw /rootmnt/ubiimage
		#if aufs.sh -l | grep -q /rootmnt/ubiimage; then
		#	mount -t aufs -o remount,mod=/rootmnt/ubiimage=rw /
			echo "UBIimage mounted in RW mode."
		#fi
	else
		echo "UBIimage is not mounted."
		exit 1
	fi
}

#readonly
ro() {
	if aufs.sh -l | grep -q /rootmnt/ubiimage; then
		# mount -t aufs -o remount,mod:/rootmnt/ubiimage=ro / # often fails...
		if mount -t aufs -o remount,del=/rootmnt/ubiimage / ; then
			mount -t aufs -o remount,append=/rootmnt/ubiimage=ro /
		else
			echo "mounting UBIimage in RO mode in aufs failed, stop all services first."
			exit 1
		fi
		if mount -t ubifs | grep -q /rootmnt/ubiimage; then
			mount -t ubifs -o remount,ro /rootmnt/ubiimage
		fi
		echo "UBIimage remounted in RO mode."
	else
		echo "UBIimage is not aufs mounted."
		exit 1
	fi
}

case $1 in
	-a) attach ;; 
	-d) detach ;;
	-r) ro ;;
	-w) rw ;;
	-l) list ;;
	*) usage ;;
esac
