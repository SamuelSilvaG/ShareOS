#!/bin/sh

umask 0022

debug=true

if test -n "$debug"; then
	exec >> /var/log/hot_aux.log 2>&1
#	set -x
	echo -e "\nUPTIME=$(cut -f1 -d" " /proc/uptime)"
	env
fi

MISCC=/etc/misc.conf
FSTAB=/etc/fstab
USERLOCK=/var/lock/userscript
SERRORL=/var/log/systemerror.log
PLED=/tmp/sys/power_led
FSCK_FORCE=/tmp/fsckboot
FSCK_LCK=/tmp/fsck_lock

if test -f $MISCC; then . $MISCC; fi

# don't do paralell fsck
check() {
	# there is a burst of add/remove events for device-mapper, let it stabilize
	if test ${MDEV:0:3} = "dm-"; then sleep 1; fi
	
	cnt=0
	while ! mkdir $FSCK_LCK >& /dev/null; do
		if ! test -f /tmp/wait-$MDEV; then
			echo "$MDEV waiting to be fscked"
			touch /tmp/wait-$MDEV
			echo $$ > /tmp/wait-$MDEV.pid
		fi
		sleep 1

		jbs=$(ls /tmp/check-*.pid 2> /dev/null)
		if test -z "$jbs"; then # dangling lock?
			cnt=$((cnt+1))
			if test $cnt = 5; then # dangling for 5 consecutive checks, take over
				break
			fi
			continue
		else
			cnt=0
		fi
		
		for i in $jbs; do # cleanup
			if kill -0 $(cat $i) 2> /dev/null; then # alive
				# that's me being checked? lvm generates extra events...
				if test "$i" = /tmp/check-$MDEV.pid; then
					echo "$MDEV is already being fscked"
					exit 0
				fi
			else # dead
				rm -f $i ${i%.pid}.log ${i%.pid}
			fi
		done
	done
	rm -f /tmp/wait-$MDEV /tmp/wait-$MDEV.pid
	
	if grep -q "^/dev/$MDEV" /proc/mounts; then
		echo "$MDEV is already mounted"
		rmdir $FSCK_LCK
		exit 0		
	fi
}

start_altf_dir() {
	if test -d /mnt/$lbl/ShareOS; then
		if test -f /mnt/$lbl/ShareOS/NOAUFS; then
			emsg="ShareOS directory found in $lbl but not used, as file NOAUFS exists on it."
			echo $emsg
			#echo "<li>$emsg</li>" >> $SERRORL
		elif test "$mopts" != "ro"; then
			if ! test -h /ShareOS -a -d "$(readlink -f /ShareOS)"; then
				echo "ShareOS directory found in $lbl"
				for i in ShareOS opt ffp home Public Backup; do
					if test -h /mnt/$lbl/ShareOS/$i; then
						rm -f /mnt/$lbl/ShareOS/$i
					fi
				done
				ln -sf /mnt/$lbl/ShareOS /ShareOS
				echo "DON'T ADD, REMOVE OR MODIFY ANY FILE UNDER /ShareOS or $(realpath /ShareOS 2> /dev/null)
	OR ANY OF ITS SUB-DIRECTORIES, OR THE SYSTEM MIGHT HANG!" > /ShareOS/README.txt
				rcs=""; toinit=""; tostart=""
				for i in $(ls /ShareOS/etc/init.d/S??* 2> /dev/null); do
					f=$(basename $i)
					isc=rc${f#S??}
					ln -sf /usr/sbin/rcscript /sbin/$isc
					rcs="$rcs $isc"
					if grep -q 'sinit()' $i; then
						toinit="$toinit $isc"
					fi
					if test -x $i; then
						tostart="$tostart $isc"
					fi
				done

				if test -n "$DELAY_NFS"; then
					snfs="/etc/init.d/S61nfs /etc/init.d/S69rmount"
				fi

				for i in $snfs $(grep -l "^NEED_ALTF_DIR=1" /etc/init.d/S??*); do
					if test -x $i; then
						f=$(basename $i)
						tostart="$tostart rc${f#S??}"
					fi
				done

				# the existence of spool on disk prevents it to spindown,
				# so use /tmp/var/spool for all spooling, not preserving data across reboots.
				if test -d /ShareOS/var/spool; then
					rm -rf /ShareOS/var/spool-old
					mv /ShareOS/var/spool /ShareOS/var/spool-old
				fi

				if ! aufs.sh -m; then
					emsg="ShareOS directory found in $lbl but not used, aufs mount failed."
					echo $emsg
					echo "<li>$emsg</li>" >> $SERRORL
					return 1
				fi

				ipkg -update # >& /dev/null # force ipkg_upgrade to update packages

				# kernel-modules might be installed, and /etc/modules specify some
				# FIXME: not needed, we already have S13modload to load km, drop or generalize it
				# and remove kernel-modules package, S13modload is its own file.
				if test -s /etc/modules; then
					echo "Loading kernel modules"
					modprobe -ab $(sed 's/#.*//' /etc/modules | tr -s '\n' ' ')
				fi

				for i in $toinit; do
					echo "$($i init)"
				done

				for i in $tostart; do
					echo "$($i restart)"
				done
			fi
		else
			emsg="ShareOS directory found in $lbl but not used, as filesystem is read-only!"
			echo $emsg
			echo "<li>$emsg</li>" >> $SERRORL
		fi
	fi
}

stop_altf_dir() {
	if test -d /mnt/$lbl/ShareOS -a "$(readlink -f /ShareOS 2> /dev/null)" = "/mnt/$lbl/ShareOS"; then

		for i in $(ls -r /ShareOS/etc/init.d/S??* 2> /dev/null); do
			f=$(basename $i)
			f=rc${f#S??}
			if $f status >& /dev/null; then
				tostop="$tostop $f"
			fi
		done

		for i in $(grep -l "^NEED_ALTF_DIR=1" /etc/init.d/S??* | sort -r); do
			f=$(basename $i)
			f=rc${f#S??}
			if $f status >& /dev/null; then
				tostop="$tostop $f"
			fi
		done

		for i in $tostop; do
			echo "$($i stop)"
		done

		for i in $(ls /ShareOS/etc/init.d/S??* 2> /dev/null); do
			f=$(basename $i)
			if ! test -f /etc/init.d/$f; then
				f=rc${f#S??}
				rm -f /sbin/$f
			fi
		done

		if aufs.sh -s && ! aufs.sh -u; then
			echo "aufs.sh unmount failed"
			start_altf_dir
			return 1
		fi
		
		rm  -f /ShareOS
	fi
}

if test "$1" = "-start-altf-dir"; then
	lbl=$(basename $(dirname $2))
	mopts="$(awk '$1 == "/dev/'$lbl'" { n = split($4, a,",")
		for (i=1;i<=n;i++) {
			if (a[i] == "ro") {
				printf "%s", a[i]; exit }
		}
	} ' /proc/mounts)"
	echo -start-altf-dir lbl="$lbl" mopts="$mopts"
	start_altf_dir
	exit $?

elif test "$1" = "-stop-altf-dir"; then
	lbl=$(basename $(dirname $2))
	echo -stop-altf-dir lbl="$lbl"
	stop_altf_dir
	exit $?

elif test "$#" != 5 -o -z "$MDEV"; then
	exit $?
fi

fsckcmd=$1
fsopt=$2
mopts=$3
lbl=$4
fstype=$5

if test "$fsckcmd" != "echo"; then
	
	trap "" 1

	check

	if test "$fsopt" = "-"; then fsopt=""; fi

	if test -f $FSCK_FORCE && echo $fstype | grep -q 'ext.' ; then
		fsopt="-fp"
		cmsg="force"
	fi

	echo "Start $cmsg fscking $MDEV"

	xf=/tmp/check-$MDEV
	logf=${xf}.log
	pidf=${xf}.pid

	touch $xf
	echo $$ > $pidf

	echo heartbeat > $PLED/trigger
	
	# launch logfile "stripper" to avoid huge log files
	(while true; do
		if test -s $logf-; then
			tail -3 $logf- > $logf
			dd if=/dev/null of=$logf- 2> /dev/null # truncate to zero
		fi
		sleep 10
	done)&
	wj=$!
	
	res="$($fsckcmd $fsopt -C5 $PWD/$MDEV 2>&1 5>> $logf-)"
	st=$?
	if test $st -ge 2; then
		mopts="ro"
		romsg="Unable to automatically fix $MDEV, err $st, trying to mount Read Only: $res"
	else
		emsg="Finish fscking $MDEV: $res"
	fi
	echo "$emsg"

	kill $wj
	rm -f $xf $logf $logf- $pidf

	if ! ls /tmp/check-* >& /dev/null; then
		echo none > $PLED/trigger
		echo 1 > $PLED/brightness
	fi

else
	emsg="No fsck command for $fstype, $MDEV not checked."
	echo $emsg
	echo "<li>$emsg</li>" >> $SERRORL
fi

# nobody is waiting, so assume nobody will appear
if ! ls /tmp/wait-*.pid >& /dev/null; then
	rm -f $FSCK_FORCE
fi

mkdir -p /mnt/$lbl
if mountpoint -q /mnt/$lbl; then
	echo "/mnt/$lbl is already being used"
	rmdir $FSCK_LCK 2> /dev/null
	return 0
fi

# record fstab date, don't change it
TF=$(mktemp)
touch -r /etc/fstab $TF
sed -i '\|^'$PWD/$MDEV'|d' $FSTAB
echo "$PWD/$MDEV /mnt/$lbl $fstype $mopts 0 0" >> $FSTAB
touch -r $TF /etc/fstab
rm $TF

# don't mount if noauto is present in mount options
if echo "$mopts" | grep -q noauto; then
	emsg="Not auto-mounting $lbl as 'noauto' is present in the mount options."
	echo $emsg
	#echo "<li>$emsg</li>" >> $SERRORL
	rmdir $FSCK_LCK 2> /dev/null
	exit 0
fi
	
res=$(mount $PWD/$MDEV 2>&1)
st=$?
rmdir $FSCK_LCK 2> /dev/null
if test $st != 0; then
	echo "Error $st mounting $MDEV: $res"
	exit 1
fi

if test -n "$romsg"; then echo "$romsg"; fi

if test -f /usr/sbin/quotaon; then
	if echo "$mopts" | grep -qE '(usrquota|usrjquota|grpquota|grpjquota)'; then
		echo "Activating quotas on $MDEV"
		quotaon -ug $PWD/$MDEV
	fi
fi

if test -d "/mnt/$lbl/Users"; then
	if ! test -h /home -a -d "$(readlink -f /home)" ; then
		echo "Users directory found in $lbl"
		ln -s "/mnt/$lbl/Users" /home
		find /home/ -maxdepth 2 -name crontab.lst | while read ln; do
			dname=$(dirname "$ln")
			cd "$dname"
			duid=$(stat -c %u .)
			fuid=$(stat -c %u crontab.lst)
			if test $duid != $fuid; then continue; fi
			user=$(ls -l crontab.lst | awk '{print $3}')
			echo "Starting crontab for $user"
			crontab -u $user crontab.lst
		done
	fi
fi

if test -d "/mnt/$lbl/Public"; then
	if ! test -h /Public -a -d "$(readlink -f /Public)" ; then
		echo "Public directory found in $lbl"
		ln -s "/mnt/$lbl/Public" /Public
	fi
fi

if test -d "/mnt/$lbl/Backup"; then
	if ! test -h /Backup -a -d "$(readlink -f /Backup)" ; then
		echo "Backup directory found in $lbl"
		ln -s "/mnt/$lbl/Backup" /Backup
	fi
fi

if test -d "/mnt/$lbl/opt"; then
	if ! test -h /opt -a -d "$(readlink -f /opt)" ; then
		echo "opt directory found in $lbl"
		ln -s "/mnt/$lbl/opt" /opt
	fi
fi

if test -d "/mnt/$lbl/ffp"; then
	if ! test -h /ffp -a -d "$(readlink -f /ffp)" ; then
		echo "ffp directory found in $lbl"
		ln -s "/mnt/$lbl/ffp" /ffp
		if test $? = 0 -a -x /etc/init.d/S??ffp; then
			rcffp start
		fi
	fi
fi

start_altf_dir

# the user script might need the ShareOS dir aufs mounted, so run it last
if test -n "$USER_SCRIPT" -a ! -f $USERLOCK; then
	if test "/mnt/$lbl" = "$(dirname $USER_SCRIPT)" -a -x "/mnt/$lbl/$(basename $USER_SCRIPT)"; then
		touch $USERLOCK
		echo "Executing \"$USER_SCRIPT start\" in background"
		$USER_SCRIPT start &
	fi
fi

