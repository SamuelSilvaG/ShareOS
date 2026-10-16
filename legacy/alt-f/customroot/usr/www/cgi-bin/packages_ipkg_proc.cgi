#!/bin/sh

. common.sh
check_cookie
read_args

CONFF=/etc/ipkg.conf
UBIROOT=/rootmnt/ubiimage
IPKGDIR=/usr/lib/ipkg

# FIXME: When updating packages with libraries, if the library is in use by some program
# the upgrade might fail without notice.
# The fast cure is to always stop all services before updating or upgrading packages.

#debug
#set -x

change_feeds() {
	sed -ir '/^src |#!#src /d' $CONFF
	for i in $(seq $nfeeds -1 1); do
		eval $(echo label="\$lbl_$i")
		if test -z "$label"; then label="feed_$i"; fi
		label=$(httpd -d "$label")
		label=$(echo "$label" | tr ' ' '-')
		
		eval $(echo feed="\$feed_$i")
		if test -z "$feed"; then continue; fi
		feed=$(httpd -d "$feed")
		
		eval $(echo cmt=\$dis_$i)
		if test -n "$cmt"; then cmt="#!#"; fi
		sed -i "1i ${cmt}src $label $feed" $CONFF
	done
}

# list all directly (present in the pkg Depends:) or indirectly (depended on the directly dependent) pkgs.
# if a given package appears more than once in the Depends: of all packages,
# than that pkg can't be removed, as it is depended-upon other installed package.

depended() {
    while test -n "$1"; do
        p=$1; shift
        if test "$p" = "Depends:" -o $p = "ipkg"; then continue; fi
        cnt=$(grep -E "Depends:.*$p([^-]|$)" /usr/lib/ipkg/status | wc -l)
        if test $cnt -gt 1; then continue; fi
		echo $p
		depended $(sed -n '/^Package: '$p'$/,/^Depends:/{/Depends:/s/,//gp}' /usr/lib/ipkg/status)
    done
}

ipkg_cmd() {
	icmd=$1
	pkg=$2
	
	if test $icmd = "-install"; then
		write_header "Installing ShareOS"

	elif test $icmd = "install"; then
		write_header "Installing ShareOS package $pkg"
		if test "$instdest" = "root"; then opt_dest="-dest root"
		elif test "$instdest" = "flash"; then opt_dest="-dest flash"
		else msg "Invalid instalation destination \"$instdest\""
		fi
		opts="-force-defaults"
		
	elif test $icmd = "upgrade"; then
		write_header "Upgrading ShareOS packages $pkg"
		opts="-force-defaults"
		
	elif test $icmd = "update"; then
		write_header "Updating ShareOS packages list"
		
	elif test $icmd = "remove"; then
		write_header "Removing ShareOS package $pkg"		
		if test "$force_remove" = "yes"; then opts="-force-depends"; fi
		if test "$rec_remove" = "yes"; then opts="-recursive"; fi
		if test "$orphan_remove" = "yes"; then
			npkg=$(depended $pkg)
			if test -n "$npkg"; then pkg=$npkg; fi
		fi
	fi

	cat<<-EOF
		<script type="text/javascript">
			function err() {
				window.location.assign(document.referrer)
			}
		</script>
	EOF

	echo "<pre>"
echo "ipkg $opt_dest $opts $icmd $pkg"
echo
	ipkg $opt_dest $opts $icmd $pkg
	if test $? = 0; then
		cat<<-EOF
			</pre>
			<p><strong>Success</strong>
			<script type="text/javascript">
				setTimeout("err()", 2000);
			</script>
		EOF
	else
		if test $icmd = "-install"; then
			ipkg -clean
		fi

		cat<<-EOF
			</pre>
			<p><strong>An error occurred </strong>
			<input type="button" value="Back" onclick="err()"></p>
		EOF
	fi
	echo "</body></html>"
	exit 0
}

if test "$install" = "Install"; then
	if test "$part" = "none"; then
		msg "You must select a filesystem where to install."
	fi

	part=$(httpd -d $part)
	mp=$(awk '/\/dev\/'$part'[[:space:]]/{print $2}' /proc/mounts)

	change_feeds

	ipkg_cmd -install $mp

elif test -n "$ClearFlash"; then
	write_header "Removing all non essential packages from flash"
	echo "<pre>"
	
	rpkgs=$(grep ^Package ${UBIROOT}${IPKGDIR}/status | cut -f2 -d" ")
	ipkg -force-depends remove $rpkgs
	
	echo "</pre>"
	goto_button Continue /cgi-bin/packages_ipkg.cgi
	exit 0
	
elif test -n "$RestoreFlash"; then
	write_header "Reinstalling default packages on flash"
	echo "<pre>"
	
	rfiles=$(cut -f1 -d" " /etc/preinst-sq)
	ipkg -d flash -force-defaults -force-reinstall install $rfiles

	echo "</pre>"
	goto_button Continue /cgi-bin/packages_ipkg.cgi
	exit 0

elif test -n "$MoveFromDisk"; then
	write_header "Moving packages from disk to flash"
	
	rpkgs=$(grep ^Package ${IPKGDIR}/status | cut -f2 -d" ")
	for i in $rpkgs; do
		if test -s ${IPKGDIR}/info/$i.list; then
			echo "<p>Moving $i"
			sed -n 's/\/ShareOS//p' ${IPKGDIR}/info/$i.list | cpio -pmd $UBIROOT 2> /dev/null
			cp -a ${IPKGDIR}/info/$i.* ${UBIROOT}${IPKGDIR}/info/
			sed -i 's/\/ShareOS/\/rootmnt\/ubiimage/' ${UBIROOT}${IPKGDIR}/info/$i.list
			sed -n "/Package: $i/,/^$/p" ${IPKGDIR}/status >> ${UBIROOT}${IPKGDIR}/status
			sed -i "/Package: $i/,/^$/d" ${IPKGDIR}/status 
		fi
	done
	goto_button Continue /cgi-bin/packages_ipkg.cgi
	exit 0


elif test -n "$BootEnable"; then
	aufs.sh -n >& /dev/null
	for i in $(seq 1 $ninstall); do
		af=$(eval echo \$altf_dir_$i)
		af=$(httpd -d "$af")
		touch $af/NOAUFS
		if test -n "$(eval echo \$BootEnable_$i)"; then
			rm -f $af/NOAUFS
		fi
	done
	mkdir -p $af/etc/init.d # fix, a defective install might exists
	aufs.sh -r >& /dev/null

elif test -n "$Delete"; then
	# FIXME: this does not remove package files installed elsewhere, e.g. /opt,
	# and we can't use 'ipkg -clean'
	altf_dir=$(httpd -d "$Delete")
	curr_altf=$(realpath /ShareOS 2> /dev/null)
	busy_cursor_start
	if test "$curr_altf" = "$altf_dir"; then
		if ! hot_aux.sh -stop-altf-dir "$curr_altf"; then
			busy_cursor_end
			msg "Current \"$curr_altf\" folder couldn't be deactivated to be deleted, stop all services first."
		fi
	fi
	if mountpoint -q "$(dirname $altf_dir)" && test "$(basename $altf_dir)" = "ShareOS"; then
		rm -rf "$altf_dir"
	fi
	busy_cursor_end
	js_gotopage /cgi-bin/packages_ipkg.cgi

elif test -n "$ActivateNow"; then
	busy_cursor_start
	if curr_altf=$(realpath /ShareOS 2> /dev/null); then
		if ! hot_aux.sh -stop-altf-dir "$curr_altf"; then
			busy_cursor_end
			msg "Current \"$curr_altf\" folder couldn't be deactivated, stop all services first."
		fi
	fi
	altf_dir=$(httpd -d "$ActivateNow")
	rm -f "$altf_dir/NOAUFS"
	hot_aux.sh -start-altf-dir "$altf_dir"
	busy_cursor_end
	js_gotopage /cgi-bin/packages_ipkg.cgi

elif test -n "$DeactivateNow"; then
	altf_dir=$(httpd -d "$DeactivateNow")
	busy_cursor_start
	if ! hot_aux.sh -stop-altf-dir "$altf_dir"; then
		busy_cursor_end
		msg "Current \"$altf_dir\" folder couldn't be deactivated, stop all services first."
	fi
	busy_cursor_end
	js_gotopage /cgi-bin/packages_ipkg.cgi

elif test -n "$CopyTo"; then
	idx=$CopyTo
	part=$(eval echo \$part$idx)
	part=$(httpd -d "$part")
	if test "$part" = "none"; then
		msg "You must select a filesystem."
	fi

	if ! blkid -s TYPE -o value /dev/$part | grep -qE 'ext(2|3|4)'; then
		msg "The destination has to be a linux ext2/3/4 filesystem."
	fi

	dest=$(awk '/\/dev\/'$part'[[:space:]]/{print $2}' /proc/mounts)
	if test -d "$dest/ShareOS"; then
		msg "The destination already has an ShareOS folder."
	fi

	altf_dir=$(eval echo \$altf_dir_$idx)
	altf_dir=$(httpd -d "$altf_dir")

	if test "$(dirname $altf_dir)" = "$dest"; then
		msg "The source and destinations are the same."
	fi

	busy_cursor_start
	cp -a $altf_dir $dest >& /dev/null
	busy_cursor_end
	js_gotopage /cgi-bin/packages_ipkg.cgi

elif test "$Submit" = "changeFeeds"; then
	change_feeds
	#if aufs.sh -s >& /dev/null; then
		ipkg_cmd update
	#fi

elif test -n "$UpdatePackageList"; then
	#if aufs.sh -s >& /dev/null; then
		ipkg_cmd update
	#fi

elif test -n "$Remove"; then
	ipkg_cmd remove $Remove

elif test -n "$Install"; then
	ipkg_cmd install $Install

elif test -n "$Update"; then
	ipkg_cmd upgrade $Update

elif test -n "$UpdateAll"; then
	ipkg_cmd upgrade
fi

#enddebug
gotopage /cgi-bin/packages_ipkg.cgi



