#!/bin/sh

. common.sh
check_cookie

write_header "TLS/SSL Certificate Setup"

check_https

MISC_CONF=/etc/misc.conf

BOX_CA_KEY=/etc/ssl/certs/rootCA.key
BOX_CA_CRT=/etc/ssl/certs/rootCA.crt

BOX_PEM=/etc/ssl/certs/server.pem
BOX_CRT=/etc/ssl/certs/server.crt
BOX_KEY=/etc/ssl/certs/server.key
BOX_CSR=/etc/ssl/certs/server.csr
BOX_CNF=/etc/ssl/server.cnf

CONF_LIGHTY=/etc/lighttpd/lighttpd.conf
MSMTP_CONF=/etc/msmtprc
ACME_CONF=/etc/acme.sh

mktt exportca_tt "Save the public root CA certificate in your computer<br>for installing into the browser or OS root trust store."

mktt saveca_tt "Save a backup copy of the root CA certificate and key in your computer."

mktt loadca_tt "Load a root CA certificate and key from a backup copy in your computer.<br>The box intranet certificate has to be recreated afterwards."

mktt createca_tt "Erases the existing root CA certificate and creates a new one.<br>The box intranet certificate has to be recreated afterwards."

mktt createcrt_tt "Erases the box current SSL certificates and creates a new one.<br>
Needed when changing the host or domain name."

mktt get_tt "Ask Let's Encrypt for a certificate for your registered and managed domain,<br>
as configured in Lighttpd."

mktt renew_tt "Ask Let's Encrypt to forcibly renew your current certificate.<br>
You shouldn't need to do this as it should be done automaticaly one month before expiration."

mktt revoke_tt "Revoke a compromissed or not anymore in use Let's Encrypt certificate,<br>
ordering Let's Encrypt to mark it as revoked and not trusted,<br>
and remove it from the box. Use only in those circunstances."

mktt remove_tt "Remove an expired, not in use or revoked Let's Encrypt certificate from the box."

cert_details() {
	# will expire within a week? 691200 sec
	oout=$(openssl x509 -in $1 -noout -text -checkend 691200 2>/dev/null)
	st=$?

	if test -z "$oout"; then
		CN=ERROR; bits=ERROR; notAfter=ERROR
		return
	fi
	#'s/.*Issuer.*CN = \(.*\)/ICN="\1"/p; \
	sout=$(echo "$oout" | sed -n \
	's/.*Issuer.*O = \(.*\), CN = \(.*\)/IO="\1" ICN="\2"/p; \
	s/.*Subject.*CN = \(.*\)/SCN="\1"/p; \
	s/.*Not After : \(.*\)/notAfter="\1"/p; \
	s/.*(\(.*\) bit)/bits="\1"/p; \
	/Alternative/{n; s/ */san="/; s/DNS:\|IP.*://g; s/,//g; s/$/"/p}')
	
	eval $sout

	if test "$st" != 0; then
		notAfter="<span class="error">$notAfter</span>"
	fi
	
	if test "$bits" -ge 1024; then
		crbits="RSA with $bits"
	else
		crbits="ECC with $bits"
	fi
}

# num bits, sel name,
sel_bits() {
	for i in 224 256 384 1024 2048 3072 4096; do
		eval bsel$i=""
		if test "$1" = "$i"; then
			eval bsel$i="selected"
		fi
	done

	cat<<-EOF
		<select name=$2 id="$2_id">
			<option $bsel224 value="224">ECC 224</option>
			<option $bsel256 value="256">ECC 256</option>
			<option $bsel384 value="384">ECC 384</option>
			<option $bsel1024 value="1024">RSA 1024</option>
			<option $bsel2048 value="2048">RSA 2048</option>
			<option $bsel3072 value="3072">RSA 3072</option>
			<option $bsel4096 value="4096">RSA 4096</option>
		</select>
	EOF
}

cat<<-EOF
	<script type="text/javascript">
	function esubmit() {
		return confirm("*** WARNING ***\n\nThe exported file shall be installed into your browser or operating system certificates root trust store to stop the anoying \"Not Secure\" browser warning when accessing the box servers through SSL.\nThe exact procedure depends on the browser and OS.\nDoing that makes your browser trust all sites that have a certificate issued with this ShareOS root CA.\nTo avoid malicious use in case the box is compromised, the ShareOS root CA private key should be protected with a strong password, which is not stored anywhere.");
	}
	function csubmit(id) {
		obj = document.getElementById(id);
		if ( obj.value == "") {
			ocol = obj.style.backgroundColor
			obj.style.backgroundColor = "#FDDD47"
			alert("You have to supply the private key password.")
			setTimeout(function(){obj.style.backgroundColor = ocol}, 1000)
			return false
		}
		return true
	}
	
	function psubmit() {
		obj1 = document.getElementById("ppass1_id")
		obj2 = document.getElementById("ppass2_id")
		pval1 = obj1.value;
		pval2 = obj2.value;
		if ( pval1 != "" && pval2 != "") {
			if (pval1 != pval2) {
				alert("The two passwords don't match.")
				return false
			}
			return true
		} else {
			ocol = obj1.style.backgroundColor
			obj1.style.backgroundColor = "#FDDD47"
			obj2.style.backgroundColor = "#FDDD47"
			alert("You have to enter and confirm the password to protect the private key.")
			setTimeout(function() { obj1.style.backgroundColor = ocol; obj2.style.backgroundColor = ocol}, 1000)
			return false
		}
	}
	</script>

	<fieldset><legend>ShareOS fake root Certificate Autority (CA)</legend>
EOF

# SSL_CERT_BITS=$(sed -n 's/^SSL_CERT_BITS="\([[:digit:]]*\)"/\1/p' $MISC_CONF)
# if test -z "$SSL_CERT_BITS"; then
# 	SSL_CERT_BITS=256
# 	sed -i '/^SSL_CERT_BITS=/d' $MISC_CONF
# 	echo "SSL_CERT_BITS=\"$SSL_CERT_BITS\"" >> $MISC_CONF
# fi

if ! test -s $BOX_CA_KEY -a -s $BOX_CA_CRT; then
	cadis=disabled
	cat<<-EOF
		<p class="error">The root CA certificate doesn't exist, it should be loaded from a backup copy or a new one created.</p>
		<p class="warn">If recreating, the old root CA certificate must be deleted<br>
		from the browser trust store and the new root CA used instead.<br>
	EOF
else
	instmsg="<p>If you have multiple ShareOS boxes all can use the same root CA certificate, use \"saveCA\" in one and \"loadCA\" in the others.</p>"

	cert_details $BOX_CA_CRT; CA_CN=$ICN
	
	if test "$bits" -ge 1024; then
		SSL_CERT_TYPE="rsa"
	else
		SSL_CERT_TYPE="ec"
	fi
	
	if openssl $SSL_CERT_TYPE -in $BOX_CA_KEY -noout -passin pass:$RANDOM >& /dev/null; then
		passwd_set=not
		cadis=disabled
	fi
			
	cat<<-EOF
		<p>Type <strong> $crbits</strong> bit, created by <strong>$ICN</strong>, valid until <strong>$notAfter</strong>. Private key is <strong><span class="error">$passwd_set</span></strong> password protected.</p>
	EOF
fi

cat<<-EOF
	<form name=certsf action="/cgi-bin/certs_proc.cgi" method="post">
	<table>
EOF

if test -n "$passwd_set"; then
	cat<<-EOF
		<tr><td>You have to supply a password to protect and use it:</td></tr>
		<tr><td>Strong password to protect the CA private key</td>
			<td><input id="ppass1_id" type=password name="pass1" value="">
			Again:<input id="ppass2_id" type=password name="pass2" value="">
			<input type=hidden name=nbits_ca value="$bits">
			<input type=submit name="ProtectKey" value="ProtectKey" onclick="return psubmit()"></td></tr>
	EOF
fi

cat<<-EOF
	<tr><td>Export CA certificate to import into browser or OS certificates trust store</td>
		<td><input $cadis type=submit name="CRTexport" value="exportCRT" onclick="return esubmit()" $(ttip exportca_tt)> </td></tr>
	</table>
	</form>
	
	$instmsg
	
	<form name=certs action="/cgi-bin/certs_proc.cgi" method="post" enctype="multipart/form-data">
	<table>
	<tr><td>CA private key password</td><td><input type=password id="capass_id"  name="pass"></td></tr>
	
	<tr><td>Save CA certificate and key to backup file</td>
		<td><input $cadis type=submit name="CAsave" value="saveCA" $(ttip saveca_tt)></td></tr>

	<tr><td>Load CA certificate and key from backup file</td>
		<td><input type=submit name=CAload value="loadCA" onclick="return csubmit('capass_id')" $(ttip loadca_tt)>
		<input type=file name="CAload2"></td>
		</tr>
		
	<tr><td>Create a new CA certificate and private key</td>
		<td><input type=submit name=createCA value="createCA" $(ttip createca_tt)>
		with $(sel_bits $bits nbits_ca) bits
		</td>
		</tr>

	</table>
	</form>
	</fieldset>
EOF

# if test -n "$cadis"; then
# 	echo "</body></html>"
# 	exit 0
# fi

if ! test -s $BOX_CRT -a -s $BOX_KEY; then
	hdmsg="<p class="error"> The box certificate does not exists, you have to create a new one.</p>"
else

	cert_details $BOX_CRT

	for i in $san; do
		if ! echo $i | grep -iqwE "$(hostname)|$(hostname -i)|$(hostname -f)"; then
		emsg="<p class="warn">The certificate field <strong>$i</strong> does not match neither the box name, box name.domain, or box IP.</p>"
		break
		fi
	done
	
	vmsg=$(openssl verify -CAfile $BOX_CA_CRT $BOX_CRT 2>&1)
	st=$?
	if test "$st" = 0; then
		ICN="$ICN (signature verified)"
	elif openssl verify -CAfile $BOX_CRT $BOX_CRT >& /dev/null; then
		ICN="$ICN (self signed)"
	else
		ICN="$ICN (signature verification failed)"
		#e=$(echo "$vmsg" | sed -n 's/error.*lookup: \(.*\)/\1/p')
		emsg="<p class="error">The box certificate could not be verified to be signed by its claimed issuer: $(echo "$vmsg" | sed -n 's/error.*lookup: \(.*\)/\1/p')</p>"
	fi
	hdmsg="<p>Type <strong> $crbits</strong> bit, issued by <strong>$ICN</strong> for a host with names of<br><strong>$(echo $san | sed 's/ /, /g')</strong>, valid until <strong>$notAfter</strong>.</p>$emsg"
fi

cat<<-EOF
	<fieldset><legend>Box intranet certificate</legend>
	$hdmsg
	<form name=certsf action="/cgi-bin/certs_proc.cgi" method="post">
	<table>
	<tr><td>Create a new certificate and key with $(sel_bits $bits nbits_cert) bits for the box:</td></tr>
	<tr><td>&nbsp;-Signed with the $CA_CN</td>
		<td><input type=submit $cadis name="createCert" value="createCert" onclick="return csubmit('passbox_id')" $(ttip createcrt_tt)></td>
		<td>CA private key password 
		<input type=password $cadis id="passbox_id" name="pass"></td>
	</tr>
	<tr><td>&nbsp;-Just self signed</td>
		<td><input type=submit name="selfSignCert" value="selfSignCert"></td>
	</tr>
	</table>
	</form>
	</fieldset>

	<fieldset><legend>Let's Encrypt internet domain certificate</legend>
	<form name=certsf action="/cgi-bin/certs_proc.cgi" method="post">
EOF

if which lighttpd >& /dev/null; then
	lighty_inst=yes
	server_root=$(sed -n 's|^var.server_root.*=.*"\(.*\)"|\1|p' $CONF_LIGHTY)
	alpndir=$(sed -n 's|^var.alpn_dir[[:space:]]*=[[:space:]]*"\(.*\)".*|\1|p' $CONF_LIGHTY)
	
	ext_domain=$(sed -n 's/^var.ext_domain[[:space:]]*=[[:space:]]*"\([a-zA-Z0-9.-]*\)".*/\1/p' $CONF_LIGHTY 2>/dev/null)

	ext_http_port=$(sed -n 's/^var.ext_http_port[[:space:]]*=[[:space:]]*\([[:digit:]]*\).*/\1/p' $CONF_LIGHTY 2>/dev/null)

	ext_https_port=$(sed -n 's/^var.ext_https_port[[:space:]]*=[[:space:]]*\([[:digit:]]*\).*/\1/p' $CONF_LIGHTY 2>/dev/null)

	https_port=$(sed -n 's/^var.https_port[[:space:]]*=[[:space:]]*\([[:digit:]]*\).*/\1/p' $CONF_LIGHTY 2>/dev/null)
	
	http_port=$(sed -n 's/^var.http_port[[:space:]]*=[[:space:]]*\([[:digit:]]*\).*/\1/p' $CONF_LIGHTY 2>/dev/null)
	
	if ! https_port_msg=$(checkport $https_port); then
		if ! echo $https_port_msg | grep -q lighttpd; then
			https_port=443
		fi
	fi

	domainip=$(nslookup $ext_domain 2>/dev/null | awk '/^Name.*'$ext_domain'/{getline; print $3}')
#	CHECKIP_SITE=checkip.dyndns.org
#	myrealip=$(wget -q $CHECKIP_SITE -O - | grep -oE '[[:digit:]]{1,3}(.[[:digit:]]{1,3}){3}')
	myrealip=$(upnpcc -s | sed -n 's/^ExternalIPAddress = \(.*\)/\1/p')

fi

MAIL_TO=$(grep ^MAILTO $MISC_CONF | cut -d= -f2 | tr -d \")
MAIL_FROM=$(grep ^from $MSMTP_CONF | cut -f2)

if ! realpath $(which acme.sh) >& /dev/null; then
	echo "<p>To have a free Let's Encrypt SSL certificate you must own a domain name, expose the box to the internet by forwarding some router ports, activate uPnP on the router and have the lighttpd webserver running.</p>
	<p>You need to install 'acmesh' first: <a href=\"/cgi-bin/packages_ipkg.cgi\">Install</a>.</p>"

elif ! realpath $(which msmtp) >& /dev/null; then
	echo "<p>You must install 'msmtp'. <a href=\"/cgi-bin/packages_ipkg.cgi\">Install</a>.</p>"
	
elif test -z "$MAIL_TO" -o -z "$MAIL_FROM"; then
	echo "<p>Please setup and test your mail to receive notifications of possible certificate renew errors. <a href=\"/cgi-bin/mail.cgi\">Setup Mail</a>.</p>"

elif ! rclighttpd status >& /dev/null; then
	if test -z "$lighty_inst"; then
		echo "<p>You must install 'lighttpd'. <a href=\"/cgi-bin/packages_ipkg.cgi\">Install</a>.</p>"
	else
		echo "<p>You must have Lighttpd configured and running.</p><p>Specify the domain name and forward the needed router ports. The router must have uPnP active.</p>
		<p>After Submiting and starting Lighttpd, verify its status by using the \"checkPort\" button. <a href=\"/cgi-bin/lighttpd.cgi\">Setup Lighttpd</a>.</p>"
	fi
	
elif test "$ext_domain" = "lighttpd"; then
	echo "<p>When configuring Lighttpd you must specify and enable the domain name that you purchased and is assigned to your external IP. <a href=\"/cgi-bin/lighttpd.cgi\">Setup Lighttpd</a></p>"

elif test -z "$domainip"; then
	echo "<p>Could't get an IP for the <strong>$ext_domain</strong> specified domain. Is it not (yet?) DNS resolved?</p>"

elif test -z "$myrealip" ; then
	echo "<p>Wasn't able to get your external IP. Please retry within a few seconds.</p>"
	
elif test "$domainip" != "$myrealip"; then
	echo "<p>Your external IP is $myrealip but it does not match the specified <strong>$ext_domain</strong> domain IP, which is $domainip.</p>"

elif test "$ext_http_port" != "80" -a "$ext_https_port" != "443"; then
	echo "<p>To validate your domain your router port 80 or 443 must be opened and forwarded to Lighttpd http listening port. <a href=\"/cgi-bin/lighttpd.cgi\">Setup Lighttpd</a></p>"
		
else
	if test -s $ACME_CONF/${ext_domain}_ecc/${ext_domain}.cer; then
		cert_details $ACME_CONF/${ext_domain}_ecc/${ext_domain}.cer
	elif test -s $ACME_CONF/$ext_domain/${ext_domain}.cer; then
		cert_details $ACME_CONF/$ext_domain/${ext_domain}.cer
	else
		echo "<p>No certificate for domain <strong>$ext_domain</strong> found</p>"
		nocert_dis="disabled"
		bits=256
	fi
	
	if ! test "$nocert_dis" = "disabled"; then
		echo "<p>Type <strong> $crbits</strong> bit, issued by <strong>$ICN/$IO</strong> for a host with names of <strong>$(echo $san | sed 's/ /, /g')</strong>, valid until <strong>$notAfter</strong>.</p>"
		getcert_dis="disabled"
	fi
	
	cat<<-EOF
		<table>
		<tr><td>Request from Let's Encrypt a new certificate with $(sel_bits $bits nbits_le) bits for this domain </td><td><input $getcert_dis type=submit name=getCert value="getCert" onclick="return confirm('Getting a certificate can take from 30 seconds to a few minutes.')" $(ttip get_tt)></td></tr>
		<tr><td>The certificate validity date is approaching, forcibly renew it (cron should do it) </td><td><input $nocert_dis type=submit name=renewCert value="renewCert" $(ttip renew_tt)></td></tr>
		<tr><td>The box or the certificate private key has been compromised, revoke and remove it </td><td><input $nocert_dis type=submit name=revokeCert value="revokeCert" $(ttip revoke_tt)></td></tr>
		<tr><td>The certificate has expired or has been revoked or I don't need it anymore,  remove it </td><td><input $nocert_dis type=submit name=removeCert value="removeCert" $(ttip remove_tt)></td></tr>
		</table>
		<input type=hidden name=ext_domain value="$ext_domain">
		<input type=hidden name=server_root value="$server_root">
		<input type=hidden name=alpndir value="$alpndir">
		<input type=hidden name=http_port value="$http_port">
		<input type=hidden name=https_port value="$https_port">
		<input type=hidden name=MAIL_TO value="$MAIL_TO">
		<input type=hidden name=MAIL_FROM value="$MAIL_FROM">
	EOF
fi

cat<<-EOF
	</form>
	</fieldset>
	</body></html>
EOF
