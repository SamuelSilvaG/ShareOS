#!/bin/sh

. common.sh
check_cookie
read_args

NAME=shellinabox

CONFF=/etc/shellinabox.conf
SIBCERT=/var/lib/shellinabox/certificate.pem

SSL_DIR=/etc/ssl/certs
BOX_CA_KEY=$SSL_DIR/rootCA.key
BOX_CA_CRT=$SSL_DIR/rootCA.crt
BOX_CNF=/etc/ssl/server.cnf

#debug

if test "$submit" = "chPort"; then
	sed -i '/^PORT/d' $CONFF
	echo "PORT=$port" >> $CONFF
	service_restart rcshellinabox
	gotopage /cgi-bin/shellinabox.cgi

elif test -n "$createCert"; then

	if test -z "$pass"; then
		msg "The root CA password can't be empty."
	fi
	
	nbits=$(openssl x509 -in $BOX_CA_CRT -noout -text 2>/dev/null | 
		sed -n 's/.*(\(.*\) bit)/\1/p')
	if test $nbits -ge 1024; then
		SSL_CERT_TYPE="rsa"
	else
		SSL_CERT_TYPE="ec"
	fi
	
	if ! httpd -d "$pass" | openssl $SSL_CERT_TYPE -in $BOX_CA_KEY \
		-passin stdin >& /dev/null; then
		msg "Incorrect password."
	fi

	write_header "Generating shellinabox SSL certificate..."
	busy_cursor_start
	
	rm -f $SSL_DIR/${NAME}.pem $SIBCERT
	
	eval $(ifconfig eth0 | awk '/inet addr/ { printf("hostip=%s netmask=%s", \
		substr($2, 6), substr($4, 6))}')
	eval $(ipcalc -n $hostip $netmask) # eval NETWORK

	# looks like shellinabox only accepts rsa
	SSL_CERT_BITS=2048
	SSL_CERT_ARGS="-newkey rsa:$SSL_CERT_BITS"

	export HOST=$(hostname) HOSTFQDN=$(hostname -f) HOSTIP=$(hostname -i) \
		DOMAIN="$(hostname -d)" BOX=$(cat /tmp/board) \
		NETWORK="$NETWORK/$netmask" REQNAME=req_dname SSL_CERT_BITS
	
	# create cert private key and sign request in one step
	openssl req -new -nodes -sha256 $SSL_CERT_ARGS \
		-keyout /tmp/${NAME}.key -out /tmp/${NAME}.csr -config $BOX_CNF >& /dev/null

	# CA sign the certificate sign request
	echo "$pass" | openssl x509 -req -days 365 -sha256 \
		-CA $BOX_CA_CRT -CAkey $BOX_CA_KEY -CAcreateserial -passin stdin \
		-in /tmp/${NAME}.csr -out /tmp/${NAME}.crt \
		-extensions v3_req -extfile $BOX_CNF >& /dev/null
	cat /tmp/${NAME}.key /tmp/${NAME}.crt > $SSL_DIR/${NAME}.pem
	chmod og-rw $SSL_DIR/${NAME}.pem
	chown $NAME:$NAME $SSL_DIR/${NAME}.pem
	rm -f /tmp/${NAME}.*
	ln -sf $SSL_DIR/${certn}.pem $SIBCERT
	
	service_restart rcshellinabox
	
	busy_cursor_end
	
	js_gotopage /cgi-bin/shellinabox.cgi
fi

if test "$submit" = "Display"; then
	if ! rcshellinabox status >& /dev/null; then
		rcshellinabox start >& /dev/null
	fi
fi

embed_page "https://${HTTP_HOST%%:*}:${PORT:-4200}" "Shell in a box Page"

#enddebug
