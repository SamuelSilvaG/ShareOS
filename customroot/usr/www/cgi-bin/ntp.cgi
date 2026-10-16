#!/bin/sh

. common.sh
check_cookie

write_header "NTP Setup"

CONFN=/etc/ntp.conf
CONFF=/etc/misc.conf

# remove adjtime method, ntpd is now builtin in busybox
if grep -q ^NTPD_DAEMON $CONFN; then
	sed -i -e '/^NTPD_DAEMON/d' -e '/NTPD_BOOT/d' -e '/NTPD_CRON/d' $CONFN
	# FIXME: cron remove "/usr/sbin/adjtime"
fi

sel_server=""; sel_client=""
if test "$NTPD_SERVER" = "yes"; then
        sel_server="checked"
else
        sel_client="checked"
fi

cat <<-EOF
	<form name=ntp action=ntp_proc.cgi method="post">
	<input type=radio $sel_server name=runasserver value=yes>
			Run as a server<br>
	<input type=radio $sel_client name=runasserver value=no>
			Run as a client only<p>
	<table>
EOF

cnt=1
while read arg server cmt; do
	if test "$arg" = "server" -a "$server" != "127.127.1.0"; then
		cat<<-EOF
			<tr><td>Server $cnt</td>
			<td><input type=text size=20 name="server_$cnt" value="$server">
			<input type=hidden name="cmt_$cnt" value="$cmt"></td></tr>
		EOF
		cnt=$(($cnt+1))
	fi
done < $CONFN

for i in $(seq $cnt $((cnt+2))); do
		echo "<tr><td>Server $i</td>
			<td><input type=text size=20 name="server_$i"></td></tr>"
done

cat<<-EOF
	</table>
	<input type=hidden name=cnt_ntp value="$i">
	<p><input type=submit value=Submit>$(back_button)
	</form></body></html>
EOF
