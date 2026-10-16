#!/bin/sh

. common.sh

check_cookie
read_args

#debug
#set -x

# this is complex: three servers (inetd/httpd/stunnel) and respective inter-dependent configuration files!

HTTPD_CONF=/etc/httpd.conf
INETD_CONF=/etc/inetd.conf
STUNNEL_CONF=/etc/stunnel/stunnel.conf
MISC_CONF=/etc/misc.conf
HTTPD_LOGF=/var/log/httpd.log

. $MISC_CONF

hostip=$(hostname -i)
netmask=$(ifconfig eth0 | awk '/inet addr/ { print substr($4, 6) }')
eval $(ipcalc -n $hostip $netmask) # evaluate NETWORK

httpd_log=false
if test "$log_en" = "yes"; then
	httpd_log=true
	touch $HTTPD_LOGF
	chmod go-r $HTTPD_LOGF
fi
sed -i '/^HTTPD_LOG=/d' $MISC_CONF
echo HTTPD_LOG=$httpd_log >> $MISC_CONF

TF=$(mktemp)

for i in $(seq 1 $httpd_cnt); do

	remip=$(eval echo \$remip_$i)

	if test -n "$remip"; then
		remip=$(httpd -d $remip)
		nip=$(echo $remip | cut -d/ -f1)
		nnetwork=$(echo $remip | cut -d/ -f2)

		if test "$nnetwork" = "$NETWORK"; then
			msg "All hosts from the local network are already\n\
allowed to access the administrative web pages."
		fi

		dis=""
		if test -n "$(eval echo \$dis_$i)"; then dis="#"; fi

		echo -e "${dis}A:$remip\t#!# Allow remote" >> $TF
	fi
done

cat<<EOF > $HTTPD_CONF
A:127.0.0.1	#!# Allow local loopback connections
D:*	#!# Deny from other IP connections
A:$NETWORK/$netmask #!# Allow local net
EOF

cat $TF >> $HTTPD_CONF
rm $TF

# as http/https servers might restart or change ports, the current connection might become broken,
# so a delayed js script is needed to reload the new URL.
# As frames from different protocols and ports can't communicate (same-origin policy), the webUI
# top page is loaded instead of the current one.

host=${HTTP_HOST%:*}
proto=${HTTP_REFERER%://*}

if test "$proto" = "http"; then
	jsport="$http_port"
else
	jsport="$https_port"
fi

html_header
cat<<-EOF
	<script type="text/javascript">

	var count = 6;
	var server = "${proto}://${host}:${jsport}"
	var testimg = server + "/help.png?" + Math.random()

	function testServer() {    
		var img = new Image()

		img.onload = function() {
			if (img.naturalHeight > 0)
				parent.document.location.replace(server)
		}

		img.onerror = function() {
			if (count) {
				count--
				setTimeout(testServer, 1000)
			} else {
				document.body.style.cursor = '';
				document.write("<html><body><br><h3><center>Timeout, try pointing your browser to " + server + "</center></h3></body></html>")
			}
		}
		img.src = testimg
	}

	setTimeout(testServer, 2000)
	document.body.style.cursor = 'wait';

	</script></body></html>
EOF

# TODO: possible lighttpd ports colision
if false; then
	if grep -q 'server.port.*=.*8080' /etc/lighttpd/lighttpd.conf; then echo yes; fi
	grep '^include.*ssl.conf' /etc/lighttpd/lighttpd.conf

	port=$(grep ^server.port $CONF_LIGHTY | cut -d" " -f3)
	sslport=$(sed -n 's/$SERVER\["socket"\] == ":\(.*\)".*/\1/p' $CONF_SSL)
fi

# port change for http
if test "$http_port" != "$oport"; then
	port_ch="y"
	case $http_port in
		8080) sed -i 's/http[\t ]/http_alt\t/' $INETD_CONF ;;
		80) sed -i 's/http_alt/http/' $INETD_CONF ;;
	esac
	#sed -i '/^#port=.*/d' $HTTPD_CONF
	#echo "#port=$http_port #!# keep commented!" >> $HTTPD_CONF
	sed -i '/^HTTPD_PORT=/d' $MISC_CONF
	echo "HTTPD_PORT=$http_port" >> $MISC_CONF
	sed -i 's/^connect.*=.*:'$oport'/connect = 127.0.0.1:'$http_port'/' $STUNNEL_CONF
fi

# port change for https
if test "$https_port" != "$osport"; then
	sport_ch="y"
	case $https_port in
		8443) sed -i 's/https[\t ]/https_alt\t/' $INETD_CONF ;;
		443) sed -i 's/https_alt/https/' $INETD_CONF ;;
	esac
	sed -i 's/^accept.*=.*443/accept = '$https_port'/' $STUNNEL_CONF
fi

srv=http
if test "$http_port" = "8080"; then
	srv=http_alt
fi

# http server change from inetd/httpd
if test "$httpd" = "server" -a "$ohttpd" = "inetd"; then
	rcinetd disable $srv >& /dev/null
	rchttp restart >& /dev/null # causes a server connection error, reload
	rchttp enable >& /dev/null # make sure that http works on boot!
elif test "$httpd" = "inetd" -a "$ohttpd" = "server"; then
	rchttp stop >& /dev/null
	rchttp disable >& /dev/null
	rcinetd enable $srv >& /dev/null
fi

ssrv=https
if test "$https_port" = "8443"; then
	ssrv=https_alt
fi

# https server change from inetd/stunnel
if test "$stunnel" = "server" -a "$ostunnel" = "inetd"; then
	rcinetd disable $ssrv swats >& /dev/null
	rcstunnel restart >& /dev/null # causes a server connection error, reload
	rcstunnel enable >& /dev/null # make sure that https works on boot!
elif test "$stunnel" = "inetd" -a "$ostunnel" = "server"; then
	rcstunnel stop >& /dev/null
	rcstunnel disable >& /dev/null
	rcinetd enable $ssrv swats >& /dev/null
fi

if test "$httpd" = "$ohttpd" -a "$http_port" != "$oport"; then
	rchttp restart >& /dev/null
fi

if test "$httpd" = "$ohttpd" -o "$stunnel" = "$ostunnel" ; then
	rcstunnel reload >& /dev/null
	rcinetd  reload >& /dev/null
fi
