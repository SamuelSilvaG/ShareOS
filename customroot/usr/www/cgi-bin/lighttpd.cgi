#!/bin/sh

. common.sh
check_cookie

CONF_LIGHTY=/etc/lighttpd/lighttpd.conf
CONF_LIGHTY2=/etc/lighttpd/modules.conf
CONF_PHP=/etc/php.ini
PHP_EDIR=/usr/lib/php5/extensions
RSYNC_SEC=/etc/rsyncd.secrets

if ! checkport >& /dev/null; then
	checkport() {
		local a=$(netstat -ltnp 2> /dev/null | sed -n 's|.*:'$1'[[:space:]].*/\(.*\)$|\1|p')
		if test -z "$a"; then return 0; fi
		echo "Port $1 currently in use by $a"
		return 1
	}
fi

if ! ipkg list_installed | grep -q kernel-modules; then
	IPV6_DIS="disabled"
	IPV6_MSG="(You have to install the kernel-modules $(uname -m) package)"
fi

if test $(grep ^server.use-ipv6 $CONF_LIGHTY | cut -d" " -f3) = '"enable"'; then
	IPV6_CHK="checked"
fi

if ! rclighttpd status >& /dev/null; then web_dis=disabled; fi

server_root=$(sed -n 's|^var.server_root.*=.*"\(.*\)"|\1|p' $CONF_LIGHTY)

http_port=$(sed -n 's/^var.http_port[[:space:]]*=[[:space:]]*\([[:digit:]]*\).*/\1/p' $CONF_LIGHTY)
if ! http_port_msg=$(checkport $http_port); then
	if ! echo $http_port_msg | grep -q lighttpd; then
		http_port=80
	fi
fi

https_port=$(sed -n 's/^var.https_port[[:space:]]*=[[:space:]]*\([[:digit:]]*\).*/\1/p' $CONF_LIGHTY)
if ! https_port_msg=$(checkport $https_port); then
	if ! echo $https_port_msg | grep -q lighttpd; then
		https_port=443
	fi
fi

ext_http_port=$(sed -n 's/.*var.ext_http_port[[:space:]]*=[[:space:]]*\([[:digit:]]*\).*/\1/p' $CONF_LIGHTY)
ext_http_en=$(sed -n 's/.*var.ext_http_en[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' $CONF_LIGHTY)

if test "$ext_http_en" = "yes"; then
	EXTHTTP_CHK="checked"
fi

ext_https_port=$(sed -n 's/.*var.ext_https_port[[:space:]]*=[[:space:]]*\([[:digit:]]*\).*/\1/p' $CONF_LIGHTY)

ext_https_en=$(sed -n 's/.*var.ext_https_en[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' $CONF_LIGHTY)

if test "$ext_https_en" = "yes"; then
	EXTHTTPS_CHK="checked"
fi

redir=$(sed -n 's/^var.redir[[:space:]]*=[[:space:]]*"\([[:alnum:]]*\)".*/\1/p' $CONF_LIGHTY)
if test "$redir" = "http"; then RDIR_CHK="checked"; fi

ext_domain=$(sed -n 's/^var.ext_domain[[:space:]]*=[[:space:]]*"\([a-zA-Z0-9.-]*\)".*/\1/p' $CONF_LIGHTY)

if test -e /etc/ssl/certs/$ext_domain.crt; then
	domain_msg="SSL certificate by: $(openssl x509 -noout -issuer -in /etc/ssl/certs/$ext_domain.crt | sed -n 's/.*issuer.*O = \(.*\),.*/\1/p')"
else
	domain_msg="No SSL certificate"
fi

if test "$ext_domain" = "lighttpd"; then
	ext_domain=""
else
	DOMAIN_CHK="checked"
fi

if grep -q '^include.*access_log.conf' $CONF_LIGHTY; then ACESSLOG_CHK="checked"; fi
if grep -q '^include.*dirlisting.conf' $CONF_LIGHTY; then DIRLST_CHK="checked"; fi
if grep -q '^include.*webdav.conf' $CONF_LIGHTY2; then WDAV_CHK="checked"; fi
if grep -q '^include.*userdir.conf' $CONF_LIGHTY2; then	USERDIR_CHK="checked"; fi
if grep -q '^include.*ssl.conf' $CONF_LIGHTY; then SSL_CHK="checked"; fi

if grep -q '^include.*fastcgi.conf' $CONF_LIGHTY2; then
	PHP_CHK="checked"
	PHP_VIS="visible"
	PHP_DISP="block"
else
	PHP_VIS="hidden"
	PHP_DISP="none"
fi

LOCAL_STYLE="
#php_id {
	visibility: $PHP_VIS;
	display: $PHP_DISP;
}
.cellfill {
	width: 100%;
}" 

write_header "Lighttpd Setup"

mktt server_root_tt "Server home folder. You have to create one, such as /mnt/sda2/WebData<br>
Files are served from the 'htdocs' subfolder, which will be automaticaly created.<br>"
mktt http_port_tt "Server HTTP port, generaly 80.<br>
If in use by the ShareOS HTTP administrative server,<br>
you have to use a different port, e.g. 8080 (or change the admin server port)."
mktt https_port_tt "HTTPS port, generaly 443.<br>
If in use by the ShareOS HTTPS adminstrative server<br>
you have to use a different port, e.g. 8443 (or change the admin https server port)."
mktt https_tt "Enable HTTPS"
mktt webdav_tt "Enable a (shared) reading and writing http server (WebDAV).<br>
Use \"webdav://$HTTP_HOST:$http_port/webdav\" or \"webdav://$HTTP_HOST:$https_port/webdav\" for write access.<br>
Some clients might require 'http:' or 'https:' instead of 'webdav:'."
mktt userdav_tt "User(s) that can use WebDAV<br>
If 'valid-user' is selected, all valid box users will share the same writing area."
mktt user_page_tt "Serve users web pages from their \"public_html\" home folder."
mktt dir_list_tt "Generate a folder listing on folders without an index file."
mktt access_tt "Generate server access loggs"
mktt php_tt "Enable PHP. Due to memory constrains enable only if needed and only the needed modules."
mktt ext_domain_tt "Registered internet domain name such as \"myhome.com\", router public IP, or leave blank for a guess.<br>
The router public IP must be DNS resolved.<br>
The necessary router ports have to be forwarded to this server, bellow, and uPnP enabled in the router.<br>
To use HTTPS you will also need a SSL certificate for the domain.<br>
You can get a free one from \"Let's Encrypt\" after setting up HTTP and/or HTTPS and using Setup->Certificates."
mktt ext_port_tt "Port that you want to use from the internet, generaly 80 for HTTP and 443 for HTTPS.<br>
The router will forward data received in the external port to the box internal ports.<br>
This will expose services running on those ports to the internet.<br>
You can check the port forward status through the \"checkPort\" button.<br>
The router must have uPnP enabled."
mktt http_redir_tt "Tell browser to re-issue request using secure HTTPS."


if ! test -x /usr/bin/php; then
	PHP_DIS="disabled"
else
	php_cols=4
	php_maxupload=$(grep upload_max_filesize $CONF_PHP | cut -d" " -f3)
	php_opt="<tr><td>&emsp;Max upload file size</td><td colspan=$((2*php_cols))><input type=text size=4 name=php_maxupload value=\"$php_maxupload\"></td></tr>"

	cnt=0; php_opt="$php_opt<tr><td  colspan=$((2*php_cols+1))>&emsp;PHP extensions:</td></tr>"
	for i in $(ls $PHP_EDIR); do
		if test "$cnt" = "0"; then php_opt="$php_opt<tr><td></td>"; fi
		bi=$(basename $i .so)
		CHK=""; if grep -q "^extension=$i" $CONF_PHP; then CHK="checked"; fi
		php_opt="$php_opt<td>$bi</td><td><input type=checkbox $CHK name=$bi value=yes>&emsp;&emsp;</td>"
		cnt=$((cnt+1))
		if test "$cnt" = "$php_cols"; then cnt=0; php_opt="$php_opt</tr>"; fi
	done
	if test "$cnt" != "0"; then
		php_opt="$php_opt<td colspan=$((2*php_cols-cnt))></td></tr>"
	fi
fi

selu=$(sed -n 's/^var.davuser[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' $CONF_LIGHTY)

useropt="<option>valid-user</option>"
if test -z "$selu"; then
	useropt="<option selected>valid-user</option>"
fi

if test "${selu:0:5}" = "user="; then
	selu=${selu:5}
fi

if test -f $RSYNC_SEC; then
	while read ln; do
		if test ${ln:0:1} = "#"; then continue; fi
		user=$(echo $ln | cut -d: -f1)
		if test "$user" = "$selu"; then
			useropt="$useropt <option selected> $user</option>"
		else
			useropt="$useropt <option> $user </option>"
		fi
	done < $RSYNC_SEC
#else
#	WDAV_DIS="disabled"
fi

cat<<-EOF
	<script type="text/javascript">
		function browse_dir_popup(input_id) {
		    start_dir = document.getElementById(input_id).value;
		    if (start_dir == "")
		    	start_dir = "/mnt";
			window.open("browse_dir.cgi?id=" + input_id + "&browse=" + start_dir, "Browse", "scrollbars=yes, width=500, height=500");
			return false;
		}
		function update_http_port(port_id, ext_port_id) {
			src = document.getElementById(port_id)
			targ = document.getElementById(ext_port_id)
			targ.innerHTML = src.value
		}
		function ssl_depend() {
			st = false
			if (document.getElementById('ssl_id').checked == false)
				st=true
			document.getElementById('redir_id').disabled = st
		}
		function php_toogle(obj) {
			targ = document.getElementById("php_id")
			if (obj.checked == true) {
				targ.style.visibility = "visible";
				targ.style.display = "block"
			} else {
				targ.style.visibility = "hidden";
				targ.style.display = "none"
			}
		}
		document.addEventListener("DOMContentLoaded", function(){ssl_depend();});
	</script>
	<form name="lighttpd" action="/cgi-bin/lighttpd_proc.cgi" method="post">
	<table>
	<tr><td>Server root</td>
		<td colspan=3><input class="cellfill" type=text id=root_id name=server_root value="$server_root" $(ttip server_root_tt)></td>
		<td><input type=button onclick="browse_dir_popup('root_id')" value=Browse></td></tr>
		
	<tr><td>Enable HTTP</td>
		<td><input type=checkbox checked name=http value=yes </td>
		<td>on port</td>
		<td><input id="http_port_id" type=text name=http_port value="$http_port" onchange="update_http_port('http_port_id', 'ext_http_port_id')" $(ttip http_port_tt)></td>
		<td>$http_port_msg</td></tr>
	<tr><td>Enable HTTPS</td>
		<td><input type=checkbox $SSL_CHK id="ssl_id" name=ssl_en value=yes onchange="ssl_depend()"$(ttip https_tt)></td>
		<td>on port</td><td><input type=text id="https_port_id" name=https_port value="$https_port" onchange="update_http_port('https_port_id', 'ext_https_port_id')" $(ttip https_port_tt)></td>
		<td>$https_port_msg</td></tr>
	<tr><td>Redirect HTTP to HTTPS</td>
		<td><input type=checkbox $RDIR_CHK id="redir_id" name=http_redir_en value=yes $(ttip http_redir_tt)></td></tr>		
	<tr><td>Serve a internet domain</td>
		<td><input type=checkbox $DOMAIN_CHK name=ext_domain_en value=yes></td>
		<td>with name</td><td><input type=text name=ext_domain value="$ext_domain" $(ttip ext_domain_tt)</td><td>$domain_msg</td></tr>
		
	<tr><td>Forward router ports</td>
		<td><input type=checkbox $EXTHTTP_CHK name=ext_http_en value=yes></td>
		<td>http from external port</td><td><input type=text name=ext_http_port value="$ext_http_port" $(ttip ext_port_tt)</td>
		<td>to internal port <span id="ext_http_port_id">$http_port</span> on this host</td></tr>
	<tr><td></td>
		<td><input type=checkbox $EXTHTTPS_CHK name=ext_https_en value=yes></td>
		<td>https from external port</td><td><input type=text name=ext_https_port value="$ext_https_port" $(ttip ext_port_tt)</td>
		<td>to internal port <span id="ext_https_port_id">$https_port</span> on this host</td></tr>
	
	<tr><td>Enable IPv6</td>
		<td><input type=checkbox $IPV6_DIS $IPV6_CHK name=ipv6_en value=yes></td>
		<td colspan=3>$IPV6_MSG</td></tr>
	<tr><td>Enable WebDAV</td>
		<td><input type=checkbox $WDAV_DIS $WDAV_CHK name=webdav_en value=yes $(ttip webdav_tt)></td>
		<td>for user</td><td><select class="cellfill" $WDAV_DIS name=user $(ttip userdav_tt)>$useropt</select></td>
		<td></td></tr>
	<tr><td>Enable User Pages</td>
		<td colspan=4><input type=checkbox $USERDIR_CHK name=userdir_en value=yes $(ttip user_page_tt)></td></tr>
	<tr><td>Enable Folder Listing</td>
		<td colspan=4><input type=checkbox $DIRLST_CHK name=dirlist_en value=yes $(ttip dir_list_tt)></td></tr>
	<tr><td>Enable Access Log</td>
		<td colspan=4><input type=checkbox $ACESSLOG_CHK name=accesslog_en value=yes $(ttip access_tt)></td></tr>
	<tr><td>Enable PHP</td><td colspan=4><input type=checkbox $PHP_DIS $PHP_CHK name=php_en value=yes onclick="php_toogle(this)" $(ttip php_tt)></td></tr>
	</table><p>
	<div id="php_id"><table>$php_opt</table></div>

	<p><input type="submit" value="Submit">$(back_button)
	<input type=submit $web_dis name="webPage" value="WebPage">
	<input type=submit name="checkPort" value="checkPort">
	</form></body></html>
EOF
