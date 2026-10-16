#!/bin/sh

. common.sh
check_cookie
read_args

#debug
#set -x

CONFM=/etc/misc.conf
CONFFSTAB=/etc/fstab

# lumount part msg
lumount() {
	if ismount $1; then
		cd /dev
		ACTION=remove DEVTYPE=partition PWD=/dev MDEV=$1 /usr/sbin/hot.sh
		if test $? != 0; then
			msg "Changes applied, but couldn't unmount \"/dev/$1\" for $2, you have to reboot."
		fi
	fi
}

# lmount part msg
lmount() {
	if ! ismount $1; then
		if isdirty $part; then
			msg "Filesystem \"$part\" is dirty, check it before mounting."
		fi

		cd /dev
		ACTION=add DEVTYPE=partition PWD=/dev MDEV=$1 /usr/sbin/hot.sh
		if test $? != 0; then
			msg "Couldn't mount \"/dev/$1\" for $2 it."
		fi
	fi
}

# $1-part $2-mopts
remount() {
	part=$1
	mopts=$2

	ne=$(awk '$1 == "/dev/'$part'" {printf("%s\t%s\t%s\t%s\t%s\t%s",
		$1, $2, $3, "'$mopts'", $5, $6)}' $CONFFSTAB)
	sed -i '\|^/dev/'$part'|d' $CONFFSTAB
	echo -n "$ne" >> $CONFFSTAB

	uuid=$(blkid -o value -c /dev/null -s UUID /dev/$part | tr '-' '_')
	sed -i '/^mopts_'${uuid}'=/d' $CONFM

	if test "$mopts" != "defaults"; then
		echo "mopts_${uuid}=$mopts" >> $CONFM
	fi
	
	lumount "$part" "setting quotas"	
	lmount "$part"
}

if test -n "$checkNow"; then
	part=$checkNow
	if ! lbl=$(plabel /dev/$part); then lbl=$part; fi
	if ! test -f /mnt/$lbl/aquota.group -a -f /mnt/$lbl/aquota.user; then
		opt="-c"
	fi
	
	html_header "Collecting quota data on $lbl..."
	busy_cursor_start
	quotaoff -ug /dev/$part >& /dev/null
	quotacheck -ug $opt /dev/$part >& /dev/null
	quotaon -ug /dev/$part >& /dev/null
	busy_cursor_end

elif test -n "$quota_global"; then
	quota_mopts='(usrquota|usrjquota|grpquota|grpjquota)'
	ext34_qmopts='jqfmt=vfsv0,usrjquota=aquota.user,grpjquota=aquota.group'
	ext2_qmopts='usrquota,grpquota'

	for i in $(seq 1 $glb_cnt); do
		enable=$(eval echo \$enable_$i)
		fs=$(eval echo \$henable_$i)
		if test -n "$enable"; then
			if ! grep -qE "^/dev/$fs.*$quota_mopts" /proc/mounts; then # is not enabled
				mqops=$(awk '$1 == "/dev/'$fs'" {
					if ($3 == "ext2") print $4 ",'$ext2_qmopts'";
					if ($3 == "ext3" || $3 == "ext4") print $4 ",'$ext34_qmopts'"}' /proc/mounts)
				remount $fs $mqops
				sleep 1 # mount is asynchronous, give it some tolerance
			fi

			active=$(eval echo \$active_$i)
			if test -n "$active"; then
				if quotaon -p /dev/$fs >& /dev/null; then
					res=$(quotaon -ug /dev/$fs 2>&1 )
					if test "$?" != 0; then
						if ! lbl=$(plabel $fs); then lbl="$fs"; fi
						if ! test -f /mnt/$lbl/aquota.user -a -f /mnt/$lbl/aquota.group; then
							msg "Before activating quotas for the first time on \"$lbl\",
you have to use the CheckNow button first."
						else
							msg "$res"
						fi
					fi
				fi
			else
				quotaoff -ug /dev/$fs >& /dev/null
			fi
		else # not enabled (disable)
			if grep -qE "^/dev/$fs.*$quota_mopts" /proc/mounts; then # enabled
				quotaoff -ug /dev/$fs >& /dev/null
				mqops=$(awk '$1 == "/dev/'$fs'" { print $4}' $CONFFSTAB)
				for j in $(echo $ext2_qmopts $ext34_qmopts | tr ',' ' '); do
					mqops=$(echo $mqops | sed 's/'$j'//')
				done
				mqops=$(echo $mqops | tr -s ,)				
				remount $fs $mqops
			fi
		fi
	done

	. $CONFM
	sed -i '/^'QUOTAMAIL'=/d' $CONFM
	if test "$quotamail" = "y"; then
		echo "QUOTAMAIL=y" >> $CONFM
	fi
	
	if test "$QUOTAMAIL" != "$quotamail"; then
		service_restart rcquota
	fi

elif test -n "$quota_ug"; then
	for i in $(seq 1 12); do
		fs=$(eval echo \$fs_$i)
		if test -z "$fs"; then break; fi
		bquota=$(eval echo \$bquota_$i)
		blimit=$(eval echo \$blimit_$i)
		fquota=$(eval echo \$fquota_$i)
		flimit=$(eval echo \$flimit_$i)
		for i in bquota blimit fquota flimit; do
			if test -z $(eval echo "\$$i"); then eval $i=0; fi
			if eval echo "\$$i" | grep -q '[^0-9kKmMgGtG]'; then
				msg "Only integers optionally followed by one leter suffix \"kKmGgGtT\", such as \"123G\", are valid."
			fi
		done
		res=$(setquota $opt $targ $bquota $blimit $fquota $flimit /dev/$fs 2>&1)
		if test "$?" != 0; then msg "$res"; fi
	done
	js_gotopage /cgi-bin/quota.cgi?repfs=$repfs
fi

#enddebug
js_gotopage /cgi-bin/quota.cgi

