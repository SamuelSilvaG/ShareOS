#!/bin/sh

. common.sh
check_cookie

html_header

#debug

if test -n "$QUERY_STRING"; then		
	parse_qstring
else
	echo "<script type="text/javascript"> window.close() </script></body></html>"
	exit 0
fi

#	ip=$(eval echo \$ip\$Get)
#	nm=$(eval echo \$nm\$Get)

	if test "$ip" = "ip=" -a "$nm" = "nm="; then
		echo "<p>You must supply a host name or an ip address to get its MAC</p>"
	elif test "$ip" != "ip=" -a "$nm" = "nm="; then
		if ! checkip $ip; then
			echo "<p>The IP must be in the form x.x.x.x, where x is greater than 0 and less then 255</p>"
		else
			tg=$ip
		fi
	elif test "$ip" = "ip=" -a "$nm" != "nm="; then	
		if ! nslookup $nm >& /dev/null; then
			echo "<p>Host with name \"$nm\" is unknown.</p>"
		else
			tg=$nm
		fi
	else
		tg=$ip
	fi
	
	if test -n "$tg"; then
		echo "<p>Getting MAC of host $tg...</p>"
		ping -W 3 -c 2 $tg >/dev/null 2>&1
		if test $? = 1; then
			echo "<p>Host is not answering, can't get its MAC.</p>"
		else
			res=$(arp $tg)
			if test "$(echo $res | cut -d" " -f1,2,3)" = "No match found"; then
				echo "<p>Host is alive but couldn't get its MAC.</p>"
			else
				mac=$(echo $res | cut -d" " -f 4)
				cat<<-EOF
					<script type="text/javascript">
						window.opener.document.getElementById("$id").value = "$mac";
						window.close()
					</script></body></html>
				EOF
				exit 0
			fi
		fi
	fi

echo "<input type=button value=\"OK\" onclick=\"window.close()\"></body></html>"

#enddebug
