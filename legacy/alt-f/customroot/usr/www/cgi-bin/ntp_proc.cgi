#!/bin/sh

. common.sh
check_cookie
read_args

CONFN=/etc/ntp.conf
CONFM=/etc/misc.conf

#debug

sed -i '/^server/d' $CONFN
echo "server 127.127.1.0" >> $CONFN

for i in $(seq 1 $cnt_ntp); do
	srv=$(eval echo \$server_$i)
	if test -n "$srv"; then
		#if grep -q "$srv" $CONFN; then continue; fi
		if ! nslookup $srv >& /dev/null; then continue; fi
		cmt=$(eval echo \$cmt_$i)
		cmt=$(httpd -d "$cmt")		
		echo "server $srv $cmt" >> $CONFN
	fi
done

sed -i '/^NTPD_SERVER/d' $CONFM
if test "$runasserver" = "yes"; then
	echo "NTPD_SERVER=yes" >> $CONFM
fi

service_restart rcntp

#enddebug
gotopage /cgi-bin/net_services.cgi

