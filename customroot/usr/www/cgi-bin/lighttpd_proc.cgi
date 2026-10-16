#!/bin/sh

. common.sh
check_cookie

CONF_LIGHTY=/etc/lighttpd/lighttpd.conf
CONF_LIGHTY2=/etc/lighttpd/modules.conf
CONF_PHP=/etc/php.ini
PHP_EDIR=/usr/lib/php5/extensions
SMBCF=/etc/samba/smb.conf
SSL_CERTS=/etc/ssl/certs

vars="ext_http_en ext_https_en ext_domain_en ipv6_en ssl_en http_redir_en webdav_en userdir_en dirlist_en accesslog_en php_en"
for i in $vars; do eval $i=no; done

if test -x /usr/bin/php; then
	for i in $(ls $PHP_EDIR); do
		bi=$(basename $i .so)
		eval $bi=no
	done
fi

read_args

#debug
#set -x

# FIXME: to remove next funtions after 1.1
if ! isport >& /dev/null; then
	isport() {
		local port lmsg="Port must be a number between 1 and 65535"
        port=$(httpd -d "$1")

        if ! isint "$port"; then
                echo "$lmsg" 
                return 1
        fi
        if test "$port" -le 0 -o "$port" -gt 65535; then
                echo "$lmsg"
                return 1
        fi

        echo $port
	}
fi

if ! isint  >& /dev/null; then
	isint() {
		echo "$1" | grep -qE '^[0-9]+$'
	}
fi

if ! service_restart >& /dev/null; then
	service_restart() {
		if $1 status >& /dev/null; then
			if ! res=$($1 restart 2>&1); then
				msg "$res"
			fi
		fi
	}
fi

# FIXME: end of remove next funtions after 1.1

if ! http_port=$(isport $http_port); then msg "http_port: $http_port"; fi
if ! https_port=$(isport $https_port); then msg "https_port: $https_port"; fi
if ! ext_http_port=$(isport $ext_http_port); then msg "ext_http_port: $ext_http_port"; fi
if ! ext_https_port=$(isport $ext_https_port); then msg "ext_https_port: $ext_https_port"; fi

if test -n "$WebPage"; then
	PORT=$http_port
	PROTO="http"
	if echo $HTTP_REFERER | grep -q '^https://'; then
		if test "$ssl_en" = "yes"; then
			PORT=$https_port
			PROTO="https"
		fi
	fi
	embed_page "$PROTO://${HTTP_HOST%%:*}:${PORT}" "Lighttpd Page"
	
elif test -n "$checkPort"; then
	html_header "Router Port forward status"
	busy_cursor_start
	echo "<pre>"
	rclighttpd check
	#cat po | sed -n 's/.*TCP[[:space:]]*\([[:digit:]]*\)->.*:\([[:digit:]]*\)[[:space:]]*.*/external \1 to internal \2/p'

	echo "</pre>"
	busy_cursor_end
	back_button
	echo "</body></html>"
	exit 0
fi

if test -n "$server_root"; then server_root=$(httpd -d "$server_root"); fi

if test "$(basename $server_root)" = "Public"; then
	msg "You must create a 'Server Root' folder."
fi

if ! res=$(check_folder $server_root); then
	msg "$res"
else
	chown lighttpd:network "$server_root"
	chmod og-w "$server_root"
fi

if ! test -d "$server_root/htdocs"; then
	mkdir -p "$server_root/htdocs"
	echo "<html><body><p>Hello Dolly</body></html>" > "$server_root/htdocs/hello.html"
	echo "<?php phpinfo(); ?>" > "$server_root/htdocs/hello.php"
	chown -R lighttpd:network "$server_root/htdocs"
	chmod -R go-w "$server_root/htdocs"
fi

if ! grep -q '\[WebData\]' $SMBCF; then
	cat <<EOF >> $SMBCF

[WebData]
	comment = Lighttpd area
	path = $server_root/htdocs
	public = no 
	available = yes
	read only = yes
EOF

else
	sed -i "/\[WebData\]/,/\[.*\]/ { s|path.*|path = $server_root/htdocs|}" $SMBCF
fi

sed -i -e 's|^var.server_root.*$|var.server_root = "'$server_root'"|' \
	-e 's|^var.http_port.*$|var.http_port = '$http_port'|' $CONF_LIGHTY

# router port forward
cmt="#"
if test "$ext_http_en" = "yes"; then cmt=""; fi
sed -i -e 's|.*var.ext_http_port.*$|var.ext_http_port = '$ext_http_port' # router port forward|' \
	-e 's|.*var.ext_http_en.*$|var.ext_http_en = "'$ext_http_en'"|' $CONF_LIGHTY

cmt="#"
if test "$ext_https_en" = "yes"; then cmt=""; fi
sed -i -e 's|.*var.ext_https_port.*$|var.ext_https_port = '$ext_https_port' # router port forward|' \
	-e 's|.*var.ext_https_en.*$|var.ext_https_en = "'$ext_https_en'"|' $CONF_LIGHTY

busy_cursor_start

# domain
if test "$ext_domain_en" = "yes"; then
	ext_domain=$(httpd -d "$ext_domain")
	
	if test -z "$ext_domain"; then
		ext_domain=$(upnpcc -s | sed -n 's/^ExternalIPAddress = \(.*\)/\1/p')
	fi

	if test -n "$ext_domain"; then
		if checkip $ext_domain; then
			dname=$(nslookup $ext_domain 2> /dev/null | awk '/^Address.*'$ext_domain'/ {print $4}')
			if test -z "$dname"; then
				msg "The $ext_domain IP is not (yet?) available on DNS servers."
			fi
			ext_domain=$dname
		elif ! nslookup $ext_domain >& /dev/null; then
			msg "The $ext_domain domain is not (yet?) available on DNS servers."
		fi
	fi

	sed -i 's|^var.ext_domain.*$|var.ext_domain = "'$ext_domain'" # set to "lighttpd" when no external domain exists|' $CONF_LIGHTY
else
	ext_domain="lighttpd"
	sed -i 's|^var.ext_domain.*$|var.ext_domain = "lighttpd" # set to qualified domain name when a internet domain exists|' $CONF_LIGHTY
fi

#IPv6
opt="disable"
if test "$ipv6_en" = "yes"; then opt="enable"; fi
sed -i 's|^server.use-ipv6.*$|server.use-ipv6 = "'$opt'"|' $CONF_LIGHTY

#SSL
# var.redir has to exists, can't be commented
sed -i 's|^var.redir.*$|var.redir = "" # set to "http" to enable redirection|' $CONF_LIGHTY

cmt="#"; cmt2="#"
if test "$ssl_en" = "yes"; then
	cmt=""
	if test "$http_redir_en" = "yes"; then
		cmt2=""
		sed -i 's|^var.redir.*$|var.redir = "http" # set to "" to disable redirection|' $CONF_LIGHTY
	fi	
fi
sed -i 's|.*\(include.*ssl.conf.*\)|'$cmt'\1|' $CONF_LIGHTY
sed -i 's|.*\("mod_redirect".*\)|'$cmt2'  \1|' $CONF_LIGHTY2

# internal ssl certificates
if test "$ssl_en" = "yes"; then	
	if test ! -f $SSL_CERTS/$ext_domain.crt -a ! -f $SSL_CERTS/$ext_domain.key; then
		# using intranet cert for Lets Encript tls-alpn handshake.
		# use cp not ln, as acme.sh uses cat to preserve perms.
		cp $SSL_CERTS/server.crt $SSL_CERTS/$ext_domain.crt
		cp $SSL_CERTS/server.key $SSL_CERTS/$ext_domain.key
		#cp $SSL_CERTS/server.pem $SSL_CERTS/$ext_domain.pem
		cp $SSL_CERTS/rootCA.crt $SSL_CERTS/$ext_domain-ca.crt # hack
		#msg "To use HTTPS for the domain '$ext_domain', the TLS/SSL certificate files\n   $SSL_CERTS/$ext_domain.crt\n   $SSL_CERTS/$ext_domain.key\nare needed but does not exists. Using self-signed certificates for now.\nYou can get free certificates from Let's Encript using HTTP ,\nuse Setup->Certificates."	
	fi
fi

#SSL port
cmt="#"
if test -n "$https_port"; then  cmt=""; fi
sed -i 's|.*var.https_port.*$|'$cmt'var.https_port = '$https_port'|' $CONF_LIGHTY

#webdav
cmt="#"
if test "$webdav_en" = "yes"; then
	cmt=""
	wdavd="$server_root/htdocs/webdav"
	if ! test -d "$wdavd"; then
		mkdir -p "$wdavd"
		chown lighttpd:network "$wdavd"
		chmod og-w "$wdavd"
	fi
	#webdav user
	opt="valid-user"
	if test "$user" != "valid-user"; then
		opt="user=$(httpd -d $user)"
	fi
	sed -i 's|.*var.davuser.*$|var.davuser = "'"$opt"'"|' $CONF_LIGHTY
fi
sed -i -e 's|.*\(include.*webdav.conf.*\)|'$cmt'\1|' \
	-e 's|.*\(include.*auth.conf.*\)|'$cmt'\1|' \
	-e 's|.*\("mod_authn_file".*\)|'$cmt'  \1|' \
	-e 's|.*\("mod_auth".*\)|'$cmt'  \1|' $CONF_LIGHTY2

cmt="#"
if test "$userdir_en" = "yes"; then cmt=""; fi
sed -i 's|.*\(include.*userdir.conf.*\)|'$cmt'\1|' $CONF_LIGHTY2

cmt="#"
if test "$dirlist_en" = "yes"; then cmt=""; fi
sed -i 's|.*\(include.*dirlisting.conf.*\)|'$cmt'\1|' $CONF_LIGHTY

cmt="#"
if test "$accesslog_en" = "yes"; then cmt=""; fi
sed -i 's|.*\(include.*access_log.conf.*\)|'$cmt'\1|' $CONF_LIGHTY

cmt="#"
if test "$php_en" = "yes"; then cmt=""; fi
sed -i 's|.*\(include.*fastcgi.conf.*\)|'$cmt'\1|' $CONF_LIGHTY2

if test "$php_en" = "yes"; then
	if test -z "$php_maxupload"; then php_maxupload="10M"; fi

	sed -i 's|.*upload_max_filesize.*|upload_max_filesize = '$(httpd -d $php_maxupload)'|' $CONF_PHP
	sed -i 's|.*post_max_size.*|post_max_size = '$(httpd -d $php_maxupload)'|' $CONF_PHP
	for i in $(ls $PHP_EDIR); do
		bi=$(basename $i .so)
		cmt=";"
		if test "$(eval echo \$$bi)" = "yes"; then cmt=""; fi
		sed -i 's|.*\(extension='$i'\)|'$cmt'\1|' $CONF_PHP
	done
fi

service_restart rclighttpd

busy_cursor_end

#enddebug
js_gotopage /cgi-bin/lighttpd.cgi
