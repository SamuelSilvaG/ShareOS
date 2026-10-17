#!/bin/sh

m2g() {
    if test "$1" -ge 1024; then
		echo "$1" | awk '{printf "%.1fGB", $1/1024}'
    else
        echo "${1}MB"
    fi
}

. common.sh
check_cookie
read_args

LOCAL_STYLE='
#ellapsed {
	position: relative;
	z-index: -1;  
	margin-left: auto;
	margin-right: auto;
	width: 33%;
	font-size: 1.5em;
}
'

wdir=$(httpd -d "$newdir")
wdir=$(echo "$wdir" | sed -n 's/^ *//;s/ *$//p')
bdir=$(dirname "$wdir")
nbdir=$(url_encode "$bdir")

#debug
#set -x

if test -n "$Stop"; then
	fop=$(ls /tmp/folders_op.* 2> /dev/null)
	if test -f "$fop"; then
		fpid=$(echo $fop | sed "s|/tmp/folders_op.\(.*\)|\1|")
		if kill $fpid >& /dev/null; then
			rm -f $fop
		fi
	fi
	js_gotopage "browse_dir.cgi"
fi

if ! echo "$wdir" | grep -q '^/mnt'; then
	msg "Only operations on /mnt sub-folders are allowed."
fi

if test -n "$srcdir"; then
	srcdir=$(httpd -d "$srcdir")
fi

if test -n "$oldname"; then
	oldname=$(httpd -d "$oldname")
fi

if test -n "$CreateDir"; then
	if test -d "$wdir"; then
		msg "Can't create, folder\n   $wdir\nalready exists."
	elif test -d "$bdir"; then
		res=$(mkdir "$wdir" 2>&1 )
		if test $? != 0; then
			msg "Creating failed:\n\n $res"
		fi
		HTTP_REFERER=$(echo "$HTTP_REFERER" | sed "s|\&browse=.*$|\&browse=$newdir|g")
	else
		msg "Can't create, parent folder\n   $bdir\ndoes not exists."
	fi
	
elif test -n "$RenameDir"; then
	if test "$oldname" = "$wdir"; then
		msg "The new and old names are identical."
	fi

	if ! test -d "$oldname"; then
		msg "Can't rename, folder\n   $oldname\ndoesn't exists."
	fi

	if test -d "$wdir"; then
		msg "Can't rename, folder\n   $wdir\nalready exists."
	fi
	
	if ! test -d "$bdir"; then
		msg "Can't rename, parent folder\n   $bdir\ndoesn't exists."
	fi

	bname=$(dirname "$oldname")
	if test "$bdir" != "$bname"; then
		msg "Can't rename, parent folders must be the same, use Cut/Paste instead."
	fi

	res=$(mv "$oldname" "$wdir" 2>&1)
	if test $? != 0; then
		msg "Renaming failed:\n\n $res"
	fi
	
	HTTP_REFERER=$(echo "$HTTP_REFERER" | sed 's|\&browse=.*$|\&browse='"$bdir"'|g')
	#js_gotopage "$HTTP_REFERER"

elif test -n "$DeleteDir"; then
	if ! test -d "$wdir"; then
		msg "Can't delete, folder\n   $wdir\ndoes not exists."
	fi

	html_header "Deleting \"$wdir\" folder"
	busy_cursor_start
	echo "<div id=\"calculating\">Calculating amount to Delete...</div>"
	
	src_sz=$(du -sm "$wdir" | cut -f1)
	src_szt=$(m2g $src_sz)
	src_mp=$(find_mp "$wdir")
	fs_free=$(df -Pm "$src_mp" | awk '/\/mnt\//{print $4}')
	
	cat<<-EOF
		<script type="text/javascript">
			document.getElementById("calculating").innerHTML = '';
		</script>		
		<div id="ellapsed"></div>
	EOF

	terr=$(mktemp -t)
	rm -rf "$wdir" 2> $terr &
	bpid=$!
	touch /tmp/folders_op.$bpid
	
	sleep_time=$(expr $src_sz \* 1000000 / 36000 / 100 + 1) # at 36GB/s gives 100 updates
	#if test $sleep_time -lt 500000; then sleep_time=500000; fi
	sleep_time=$((sleep_time < 500000 ? 500000 : sleep_time))
	
	while kill -0 $bpid >& /dev/null; do
		op_free=$(df -Pm "$src_mp" | awk '/\/mnt\//{print $4}') 
		op_rm=$((op_free - fs_free))
		el=$((op_rm * 100 / (src_sz+1)))
		echo $el > /tmp/folders_op.$bpid
		cat<<-EOF
		<script type="text/javascript">
			document.getElementById("ellapsed").innerHTML = '$(drawbargraph $el $(m2g $op_rm)/$src_szt | tr "\n" " " )';
		</script>
		EOF
		usleep $sleep_time
	done
	wait $bpid
	st=$?

	busy_cursor_end

	res=$(cat $terr)
	rm -f /tmp/folders_op.$bpid $terr
	if test $st != 0; then
		msg "Deleting failed:\n\n $res"
	fi

	HTTP_REFERER=$(echo "$HTTP_REFERER" | sed 's|\&browse=.*$|\&browse='"$nbdir"'|g')
	js_gotopage "$HTTP_REFERER"

elif test -n "$Copy" -o -n "$Move" -o -n "$CopyContent"; then
	if ! test -d "$srcdir"; then
		msg "Failed, folder\n   $srcdir\n does not exists."
	fi

	sbn=$(basename "$srcdir")
	if test -d "${wdir}/${sbn}" -a -z "$CopyContent"; then
		msg "Failed, folder\n   $wdir\n already contains a folder named\n   $sbn"
	fi

	if test "$op" = "CopyContent"; then
		op="Copy Content"
	fi

	html_header "$op from \"$srcdir\" to \"$wdir\""
	busy_cursor_start
	
	echo "<div id=\"calculating\">Calculating amount to $op...</div>"
	
	src_mp=$(find_mp "$srcdir")
	dst_mp=$(find_mp "$wdir")
		
	src_sz=$(du -sm "$srcdir" | cut -f1)
	dst_free=$(df -Pm "$dst_mp" | awk '/\/mnt\//{print $4}')

	busy_cursor_end

	src_szt="$(m2g $src_sz)"
	dst_freet="$(m2g $dst_free)"
	
	cat<<-EOF
	<script type="text/javascript">
		document.getElementById("calculating").innerHTML = '';
	</script>
	EOF
	
	if test -n "$Copy" -o -n "$CopyContent"; then
		if test "$src_sz" -gt "$dst_free"; then
			msg "Can't $op, $src_szt needed and only $dst_freet are available."
		fi
	elif test "$src_mp" != "$dst_mp"; then
		if test "$src_sz" -gt "$dst_free"; then
			msg "Can't $op, $src_szt needed and only $dst_freet are available."
		fi
	fi
	
	busy_cursor_start
	
	cat<<-EOF
	<form action="/cgi-bin/dir_proc.cgi" method="post">
		<div id="ellapsed">$(drawbargraph 0 "0MB/$src_szt")</div><br>
		<div align=center><span id="eta">ETA: --</span>&nbsp;<input type=submit name="Stop" value="Stop"></div>
	</form>
	EOF
	
	exist_sz=$(df -Pm "$dst_mp" | awk '/\/mnt\//{print $3}')
	terr=$(mktemp -t)
	startt=$(date +%s)
	if test -n "$Copy" -o -n "$CopyContent"; then
		if test -n "$CopyContent"; then
			cd "$srcdir"
			srcdir="."
		else
			cd "$(dirname "$srcdir")"
			srcdir=$(basename "$srcdir")
		fi
		cp -a "$srcdir" "$wdir" 2> $terr &
	else
		mv -f "$srcdir" "$wdir" 2> $terr &
	fi

	bpid=$!
	touch /tmp/folders_op.$bpid

	# no harm...?
	#if test "$src_sz" -le 0 -o "$dst_free" -le 0 -o "$exist_sz" -le 0; then
	#	msg "Oops, src_sz=$src_sz dst_free=$dst_free exist_sz=$exist_sz"
	#fi

	sleep_time=$(expr $src_sz \* 1000000 / 40 / 100) # at 40MB/s gives 100 updates.
	# $(()) can overflow  
	sleep_time=$((sleep_time > 30000000 ? 30000000 : sleep_time < 500000 ? 500000 : sleep_time))
	
	sleep 1
	
	while kill -0 $bpid >& /dev/null; do
		curr_sz=$(df -Pm "$dst_mp" | awk '/\/mnt\//{print $3}') 
		mv_sz=$((curr_sz - exist_sz))
		if test "$mv_sz" = 0; then continue; fi
		el=$((mv_sz * 100 / src_sz))
		echo $el > /tmp/folders_op.$bpid
		eta=$(( (src_sz - mv_sz) / (mv_sz/($(date +%s) - startt)) ))
		hr=$((eta/3600)); min=$(((eta%3600 + 59)/60)) # ceil()
		if test "$hr" = 0; then
			etat=$(printf "ETA: %dmin" $min )
		else
			etat=$(printf "ETA: %dhour %dmin" $hr $min )
		fi
		cat<<-EOF
		<script type="text/javascript">
			document.getElementById("ellapsed").innerHTML = '$(drawbargraph $el "$(m2g $mv_sz)/$src_szt" | tr "\n" " " )';
			document.getElementById("eta").innerHTML = "$etat";
		</script>
		EOF
		usleep $sleep_time
	done
	wait $bpid
	st=$?

	busy_cursor_end

	rm -f /tmp/folders_op.$bpid
	res=$(cat $terr)
	rm -f $terr

	if test $st != 0; then
		#msg "$op failed:\n\n$res"
		echo "<h4>$op failed:</h4><pre>$res</pre>$(back_button)</body></html>"
		exit 1
	fi

	js_gotopage "$HTTP_REFERER"

elif test -n "$Permissions"; then
	nuser="$(httpd -d $nuser)"
	ngroup="$(httpd -d $ngroup)"
		
	if test -z "$recurse"; then
		optr="-maxdepth 0"
	fi

	if test -z "$toFiles"; then
		optf="-type d"
	fi

	if test -n "$setgid"; then
		setgid="s"
	fi

	find "$wdir" $optr $optf -exec chown "${nuser}:${ngroup}" {} \;
	find "$wdir" $optr $optf -exec chmod u=$p2$p3$p4,g=$p5$p6$p7$setgid,o=$p8$p9$p10 {} \;

	HTTP_REFERER=$(httpd -d "$goto")
fi

#enddebug
gotopage "$HTTP_REFERER"

