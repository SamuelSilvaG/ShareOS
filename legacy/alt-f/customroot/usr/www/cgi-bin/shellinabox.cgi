#!/bin/sh

. common.sh
check_cookie

write_header "ShellinaBox Setup"

CONFF=/etc/shellinabox.conf
SIBCERT=/var/lib/shellinabox/certificate.pem

SSL_DIR=/etc/ssl/certs
BOX_CA_KEY=$SSL_DIR/rootCA.key

. $CONFF

if test -z "$PORT"; then PORT=4200; fi

cat <<-EOF
	<form name=siab action=shellinabox_proc.cgi method="post">
EOF

if test -h $SIBCERT -a \
	"$(realpath $SIBCERT 2> /dev/null)" = "$SSL_DIR/shellinabox.pem" -a \
	"$(openssl verify $SIBCERT 2> /dev/null)" = "${SIBCERT}: OK"; then
	certexists=true
	wd="<p>A good SSL certificate exists. A new one can be created and signed with the ShareOS \"fake root CA\"</p>"
	cCert="reCreateCert"
elif test -s $SIBCERT ; then
	if test "$(openssl x509 -noout -subject_hash -in $SIBCERT)" = \
		"$(openssl x509 -noout -issuer_hash -in $SIBCERT)"; then
		wd="<p class=\"blue\">A SSL certificate exists but is self-signed, create a new one and sign it with the ShareOS \"fake root CA\"</p>"
		cCert="createCert"
	fi
else   # no cert, create one and sign it
	wd="<p class=\"blue\">A SSL certificate needs to be created and signed with the ShareOS \"fake root CA\"</p>"
	cCert="createCert"
fi

cat <<-EOF
	$wd
	<table>
	<!--input type=hidden name=SSL_CERT_TYPE value="$SSL_CERT_TYPE"-->
	<tr><td>ShareOS "fake root CA" password:</td>
		<td><input type=password name="pass" value=""></td>
		<td><input type=submit name="createCert" value="$cCert"></td></tr>
	<tr><td>Listen on port:</td>
		<td><input type=text size=20 name="port" value="$PORT"></td>
		<td><input type=submit name="submit" value="chPort"></td>
	</tr>
	<tr><td>web UI:</td>
	<td><input type=submit name="submit" value="Display"></td>
	</tr>
	</table></form></body></html>
EOF
