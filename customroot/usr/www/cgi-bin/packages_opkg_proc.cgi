#!/bin/sh

. common.sh
check_cookie
read_args

#debug
#set -x

PATH=$PATH:/opt/bin:/opt/sbin
CONFF=/opt/etc/opkg.conf

opkg_cmd() {
	opt=$1
	if test $1 = "install"; then
		write_header "Installing Entware package $2"
	elif test $1 = "remove"; then
		write_header "Removing Entware package $2"
		opt="--autoremove $opt"
	elif test $1 = "update"; then
		write_header "Updating Entware packages list"
	elif test $1 = "upgrade"; then
		write_header "Upgrading all Entware packages"
	fi

	cat<<-EOF
		<script type="text/javascript">
			function err() {
				window.location.assign(document.referrer)
			}
		</script>
	EOF

	busy_cursor_start
	echo "<pre>"
	opkg $opt $2				
	if test $? = 0; then
		bmsg="Continue"
		lmsg="Success"
	else
		bmsg="Back"
		lmsg="An error occurred"
	fi
	cat<<-EOF
		</pre>
		<p><strong>$lmsg </strong>
		<input type="button" value="$bmsg" onclick="err()"></p>
	EOF
	
	busy_cursor_end	
	echo "</body></html>"
	exit 0
}

#$1: part
move_opt() {
	if test "$1" = "none"; then
		msg "You must select a filesystem first."
	fi
	
	part=$(httpd -d $1)
	mp=$(awk '/\/dev\/'$part'[[:space:]]/{print $2}' /proc/mounts)
	mkdir -p $mp/opt
	
	if test -d /opt -a -L /ShareOS -a ! -L /ShareOS/opt; then # /opt exists under /ShareOS
		# stop installed running (or depended by) services installed under /ShareOS/opt
		
		tostop="owncloud tt-rss aria2web nzbgetweb" # relies on lighttpd
		rctostop="rctwonky rcsyncthing rcpyload rcsabnzbd rcsickbeard rccouchpotato rccouchpotato2"

		for i in $rctostop; do
			$i stop >& /dev/null
		done
		for i in $tostop; do
			if ipkg status $i | grep -q installed; then
				rclighttpd stop >& /dev/null
			fi
		done
	fi

	# relocate /opt to new location
	if test -d /opt -a "$(realpath /opt 2> /dev/null)" != "$mp/opt"; then
		busy_cursor_start
		aufs.sh -n # just in case /opt exists under /ShareOS
		mv /opt/* $mp/opt
		rmdir /opt >& /dev/null || rm /opt >& /dev/null
		aufs.sh -r
		busy_cursor_end
	fi
	
	ln -sf $mp/opt /opt	
}

if test -n "$MoveTo"; then
	move_opt $part
	js_gotopage "/cgi-bin/packages_opkg.cgi"
	
elif test "$install" = "Install"; then

	move_opt $part
	
	write_header "Installing Entware"
	busy_cursor_start

	feed=$(httpd -d $feed_1)
	echo "<p><strong>Downloading...</strong></p><pre>"
	if ! wget $feed/installer/generic.sh -O /tmp/generic.sh; then
		echo "</pre><p><strong>Downloading the installer from $feed failed.</strong></p>"
		rm -f /tmp/generic.sh
		err=1
	else
		echo "</pre><p><strong>Installing...</strong></p><pre>"
		if ! sh /tmp/generic.sh; then
			echo "</pre><p><strong>Executing the installer failed.</strong></p>"
			err=1
		fi
	fi

	busy_cursor_end

	if test -z "$err"; then
		if ! test -d /ShareOS/etc/init.d; then
			aufs.sh -n
			mkdir -p /ShareOS/etc/init.d # fix, a defective install might exists
			aufs.sh -r
		fi
		cat<<-EOF  >/etc/init.d/S81entware
			#!/bin/sh

			DESC="Software repository for network attached storages, routers and other embedded devices."
			TYPE=user

			. /etc/init.d/common

			if ! test -f /opt/etc/init.d/rc.unslung; then
				echo "No Entware installation found."
				exit 1    
			fi
			
			if test -z "\$(find /opt/etc/init.d/ -name 'S[0-9]*')"; then
				echo "No Entware init scripts found."
				exit 1
			else
				echo "entware \$1..."
			fi
 
			export PATH=/opt/bin:/opt/sbin:\$PATH

			case "\$1" in
					start) /opt/etc/init.d/rc.unslung start ;;
					stop) /opt/etc/init.d/rc.unslung stop ;;
					status) /opt/etc/init.d/rc.unslung check ;;
					restart) /opt/etc/init.d/rc.unslung restart ;;
					*) usage \$0 "start|stop|status|restart" ;;
			esac
		EOF
		ln -sf /usr/sbin/rcscript /sbin/rcentware
	fi

# 	cat<<-EOF
# 		</pre>
# 		<input type="button" value="Continue" onclick="window.location.assign(document.referrer)">
# 		</body></html>
# 	EOF
	echo "</pre>"
	goto_button Continue /cgi-bin/packages_opkg.cgi
	exit 0

elif test -n "$RemoveAll" -o -n "$Uninstall"; then
	write_header "Removing Entware"
	echo "<pre>"
	busy_cursor_start
	rcentware stop >& /dev/null
	for i in bin etc lib sbin share tmp usr var; do
		rm -rf /opt/$i
	done
	busy_cursor_end
	echo "</pre>"
	rm -f /etc/init.d/S81entware /sbin/rcentware
	js_gotopage "/cgi-bin/packages_opkg.cgi"

elif test "$Submit" = "changeFeeds"; then
	sed -i '\|src/gz|d' $CONFF
	for i in $(seq 1 $nfeeds); do
		eval $(echo feed=\$feed_$i)
		if test -z "$feed"; then continue; fi
		feed=$(httpd -d "$feed")
		eval $(echo cmt=\$dis_$i)
		if test -n "$cmt"; then cmt="#!#"; fi
		echo "${cmt}src/gz feed_$i $feed" >> $CONFF
	done
	opkg_cmd update

elif test -n "$UpdatePackageList"; then
	opkg_cmd update

elif test -n "$Remove"; then
	opkg_cmd remove $Remove

elif test -n "$Install"; then
	opkg_cmd install $Install

elif test -n "$Update"; then
	opkg_cmd install $Update

elif test -n "$UpdateAll"; then
	opkg_cmd upgrade

elif test -n "$Upgrade"; then
	rcentware stop >& /dev/null
	
	arch=armv5-3.2; oarch=armv5soft
	feed="https://bin.entware.net/armv5sf-k3.2"
	if grep -q DNS-327L /tmp/board; then
		feed="https://bin.entware.net/armv7sf-k3.2"
		arch=armv7-3.2; oarch=armv7soft
	fi
	
	sed -i 's|src/gz.*|src/gz entware '$feed'|' $CONFF
	cat<<-EOF >> $CONFF
		arch all 50
		arch $oarch 100
		arch $arch 150
	EOF
	
	opkg update 2>&1 # sometimes it error out
	if res=$(opkg update 2>&1); then
		opkg_cmd upgrade
	else
		msg "update failed: $res"
	fi

elif test -n "$search"; then
	gotopage "/cgi-bin/packages_opkg.cgi?search=$search"
fi

#enddebug
gotopage /cgi-bin/packages_opkg.cgi



