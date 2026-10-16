#!/bin/sh

. common.sh
check_cookie
read_args

kernel_file=/tmp/kernel
initramfs_file=/tmp/initramfs
sqimage_file=/tmp/sqimage
defaults_file=/tmp/defaults

if test "$flash" = "Abort"; then
	rm -f $kernel_file $initramfs_file $sqimage_file $defaults_file > /dev/null 2>&1
	gotopage /cgi-bin/firmware.cgi
fi

# $1-file, $2-device, $3-msg
flash() {
	type=$(cat /sys/class/mtd/mtd0/type)
	if test "$type" = "nand"; then
		nand_flash $*
	elif test "$type" = "nor"; then
		nor_flash $*
	else
		msg "bummer!"
	fi
}

flash_error() {
	rm -f $TF $kernel_file $initramfs_file $sqimage_file $defaults_file
	echo "none" > /tmp/sys/power_led/trigger
	echo "<strong><span class=\"error\">Failed</span></strong></p><p>You can repeat the fw download and firmware upgrade using HTTP<br>
	after stopping all running processes (System->Utilities->Services, StopAll)<br>or \"TryIt\" another firmware, but <strong>don't reboot or poweroff the box until success</strong><br> or you will need to buy and solder a serial cable into the box to make it work again.</p><pre>$1</pre></body></html>"
	rcsysctrl start >& /dev/null
	exit 1
}

# rev-A:
# - Flashing kernel, it should take about 21 seconds: 23 Verifying... OK
# - Flashing rootfs, it should take about 86 seconds: 91 Verifying... OK
# 
# rev-B:
# - Flashing kernel, it should take about 21 seconds: 30 Verifying... OK
# - Flashing rootfs, it should take about 86 seconds: 109 Verifying... OK
# 
# rev-C:
# - Flashing kernel, it should take about 21 seconds: 47 Verifying... OK
# - Flashing rootfs, it should take about 86 seconds: 195 Verifying... OK 

nor_flash() {
	sz=$(stat -c %s $1)
	tm=$(expr $sz / 75126 + 1); tm2=$(expr $tm \* 25 / 10)
	wait_count_start "<p>Flashing $3, it should take between $tm and $tm2 seconds"
	cat $1 > /dev/$2
	wait_count_stop

	echo "Verifying... "
	sync; echo 3 >/proc/sys/vm/drop_caches # shouldn't be needed here
	TF=$(mktemp)
	dd if=/dev/$2 of=$TF bs=$sz count=1 >& /dev/null
	if ! cmp $1 $TF >& /dev/null; then flash_error; fi
	echo "OK</p>"
	rm -f $TF
}

nand_flash() {
	sz=$(stat -c %s $1)
	ebs=$(cat /sys/class/mtd/$sqimage_mtd/erasesize)
	bbc=$(cat /sys/class/mtd/$sqimage_mtd/bad_blocks)
	ebc=$(expr $(cat /sys/class/mtd/$sqimage_mtd/size) / $ebs) # device erase block count
	ecnt=$(expr \( $sz + $ebs - 1 \) / $ebs + $bbc) # ceil(sz/ebs) + possible bad blocks
	if test $ecnt -ge $ebc; then ecnt=0; fi # full device
	
	echo "<p>$3: Erasing $ecnt eraseblocks...&nbsp;"
	if ! res=$(flash_erase -q /dev/$2 0 $ecnt 2>&1); then flash_error "flash_erase: $res"; fi
	
	echo "writing $sz bytes...&nbsp;"
	if ! res=$(nandwrite -qmp /dev/$2 $1 2>&1); then flash_error "nandwrite: $res"; fi

	echo "reading...&nbsp;"
	sync; echo 3 >/proc/sys/vm/drop_caches # shouldn't be needed here
	TF=$(mktemp)
	if ! res=$(nanddump -ql $sz -f $TF /dev/$2 2>&1); then flash_error "nanddump: $res"; fi
	
	echo "verifying...&nbsp;"
	if ! res=$(cmp $TF $1) ; then flash_error "cmp: $res"; fi
	rm -f $TF
	echo "OK</p>"
}

check_fwfiles() {
	if ! test -f $kernel_file -a -f $initramfs_file; then
		rm -f $kernel_file $initramfs_file $sqimage_file $defaults_file
		cat<<-EOF
			<br>
			<form action="/cgi-bin/firmware.cgi" method="post">
			Kernel and/or ramdisk file missing <input type="submit" value="Retry">
			</form></body></html>
		EOF
		exit 0
	fi

	if test "$flash_defaults" = "flash" -a ! -s $defaults_file; then
		rm -f $kernel_file $initramfs_file $sqimage_file $defaults_file
		cat<<-EOF
			<br>
			<form action="/cgi-bin/firmware.cgi" method="post">
			defaults file missing or empty <input type="submit" value="Retry">
			</form></body></html>
		EOF
		exit 0
	fi
}

html_header "Firmware Updater"

if test "$flash" = "SpecialReboot"; then
	rm -f $initramfs_file $kernel_file $sqimage_file $defaults_file
	dd if=/dev/mtdblock2 of=/boot/zImage bs=64 skip=1 >& /dev/null
	dd if=/dev/mtdblock3 of=/boot/rootfs.arm.sqmtd bs=64 skip=1 >& /dev/null

elif test "$flash" = "TryIt"; then
	check_fwfiles
	dd if=$kernel_file of=/boot/zImage bs=64 skip=1 >& /dev/null
	dd if=$initramfs_file of=/boot/rootfs.arm.sqmtd bs=64 skip=1 >& /dev/null
	rm -f $initramfs_file $kernel_file $sqimage_file $defaults_file

elif test "$flash" = "FlashIt"; then
	check_fwfiles
	echo "<h3 class=\"error\">Don't poweroff or reboot the box until instructed to do it!<br>The upgrade takes at most five minutes to complete, and progress messages should be displayed.</h3><h4 class=\"warn\">If you suspect that something went wrong, you can try to repeat the firmware file download and upgrade using HTTP instead of HTTPS<br>
	after stopping all running processes (System->Utilities->Services, StopAll).<br></h4>"

	rcall stop >& /dev/null

	echo timer > /tmp/sys/power_led/trigger
	echo 50 > /tmp/sys/power_led/delay_off 
	echo 50 > /tmp/sys/power_led/delay_on

	if grep -qE 'DNS-321-Ax|DNS-323' /tmp/board; then
		kernel_mtd=mtd2
		initramfs_mtd=mtd3
		defaults_mtd=mtdblock0
		sqimage_mtd=""
	elif grep -qE 'DNS-327L|DNS-320-[AB]x|DNS-320L-Ax|DNS-325-Ax|DNR-322L-Ax' /tmp/board; then
		kernel_mtd=mtd1
		initramfs_mtd=mtd2
		sqimage_mtd=mtd3
		if grep -qE 'DNS-327L' /tmp/board; then
			fs_type="-t ubifs"
			defaults_mtd=ubi0_0
		else
			fs_type="-t jffs2"
			defaults_mtd=mtdblock5
		fi
	else
		rcsysctrl start
		msg "bummer!"
	fi

	# do this before flashing kernel/initrd if ubi is in use and can't be unmounted
	if test -s $sqimage_file; then
		# if UBI is in use, stop using it to free the mtd device for flashing
		if mount -t ubifs | grep -q /rootmnt/ubiimage; then
			if aufs.sh -l | grep -q /rootmnt/ubiimage; then
				if ! mount -t aufs -o remount,del=/rootmnt/ubiimage /; then
					flash_error "Some processes are still running, stop them first."
				fi
			fi
			if ! umount /rootmnt/ubiimage 2>/dev/null; then
				# insert where /rootmnt/ro currently is; ro will be at bottom
				ix=$(basename $(grep -l /rootmnt/ro /sys/fs/aufs/*/br?))
				mount -t aufs -o remount,ins:${ix#br}:/rootmnt/ubiimage /
				flash_error "Some processes are still running, stop them first."
			fi
		fi
		ubidetach -p /dev/$sqimage_mtd  >&	/dev/null
	fi

	flash $kernel_file $kernel_mtd kernel
	flash $initramfs_file $initramfs_mtd rootfs

	if test -s $sqimage_file; then
		magic1=$(dd if=$sqimage_file bs=1 count=4 2> /dev/null)
		magic2=$(dd if=$sqimage_file bs=1 count=4 skip=2048 2> /dev/null)
		if test "$magic1" = "UBI#" -a "$magic2" = "UBI!"; then 
			# for a UBI image an alternative flashing method is required
			echo "<p>image: UBI formatting...&nbsp;"	
			if ! res=$(ubiformat -qy -s 2048 -O 2048 -f $sqimage_file /dev/$sqimage_mtd 2>&1); then
				flash_error "ubiformat: $res"
			fi
			# make sure all went well and it can be attached
			if ! res=$(ubiattach -d 1 -p /dev/$sqimage_mtd -O 2048 2>&1); then
				flash_error "ubiattach: $res"
			fi
			ubidetach -p /dev/$sqimage_mtd >& /dev/null
			echo "OK</p>"
		else
			flash $sqimage_file $sqimage_mtd sqimage
		fi
	fi
	
	case "$flash_defaults" in
		"none")
			;;

		"clear")
			echo "<p>Erasing flashed settings, it should take some 5 seconds..."
			loadsave_settings -cf >& /dev/null
			;;

		"flashfile")
			echo "<p>Flashing new settings, it should take some 5 seconds..."
			TD=$(mktemp -d)
			mount $fs_type /dev/$defaults_mtd $TD
			rm -f $TD/*
			tar -C /tmp -xzf $defaults_file
			cp -f /tmp/default/* $TD
			umount $TD
			rm -rf $TD /tmp/default
			;;

		"recover")
			echo "<p>Recovering vendors settings from backup, it should take some 5 seconds..."
			loadsave_settings -rc  >& /dev/null
			;;
	esac

	# FIXME: ShareOS is not probably mounted at this time!
	# But fixup can't be done earlier as it might contain fixes needed for flashing...
	# remove applied fixes and other customizations under /ShareOS,
	# avoiding that changed files with the same name in the new firmware will be shadowed
	fixup clean >& /dev/null

	rcsysctrl start >& /dev/null
	rm -f $kernel_file $initramfs_file $sqimage_file $defaults_file
	echo "none" > "/tmp/sys/power_led/trigger"
fi

cat<<-EOF
	<form action="/cgi-bin/sys_utils_proc.cgi" method="post">
	You should reboot the box now for the new firmware to become active.
	<input type=submit name="action" value="Reboot" onClick="return confirm('The box will reboot now.\nYou will be connected again in 60 seconds.\n\nProceed?')">
	</form></body></html>
EOF
