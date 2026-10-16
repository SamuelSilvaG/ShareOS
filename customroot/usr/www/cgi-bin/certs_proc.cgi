#!/bin/sh

. common.sh
check_cookie

SSL_DIR=/etc/ssl/certs

BOX_CA_KEY=$SSL_DIR/rootCA.key
BOX_CA_CRT=$SSL_DIR/rootCA.crt
BOX_CA_PEM=$SSL_DIR/rootCA.pem

BOX_PEM=$SSL_DIR/server.pem
BOX_CRT=$SSL_DIR/server.crt
BOX_KEY=$SSL_DIR/server.key
BOX_CSR=$SSL_DIR/server.csr
BOX_CNF=/etc/ssl/server.cnf

MISC_CONF=/etc/misc.conf
CONF_LIGHTY=/etc/lighttpd/lighttpd.conf

INST_DIR=$SSL_DIR
ACME_CONF=/etc/acme.sh
ACME_MODE="--test"

# if test -n "$ACME_MODE"; then
# 	INST_DIR=/etc/lighttpd/certs
# 	mkdir -p $INST_DIR
# fi

if ! test -d /ShareOS/$SSL_DIR; then
	aufs.sh -n
	mkdir -p /ShareOS/$SSL_DIR
	aufs.sh -r
fi

ext_domain=$(httpd -d "$ext_domain")

# FIXME: to remove after 1.1, updated upload_file() and upload_file_inner() from common.sh
upload_file_inner() {
	local s e of files scmd lcnt ln flen fname_ret oumask=$(umask)
	umask 077

	# split transfer into several temp files
	while test "$#" -gt 1; do
		s=$(($1+1)) # skip only boundary
		e=$(($2-1))
		#echo $s-$e
		shift
		of=$(mktemp)
		files="$files $of"
		scmd="$scmd -e '$s,$e {w $of
}'"
	done

	# stupid thing, eval has to be used!
	eval sed -n "$scmd" $xxupfile
	rm $xxupfile
	
	# remove HTTP headers from each file, give them the expected name,
	# define var=value for text forms
	for i in $files; do
		lncnt=0;
		while read -r ln; do
			ln=$(echo "$ln"|dos2unix) # strip CR/LF HTTP EOL
			
			if echo $ln | grep -q "^Content-Disposition: "; then
				name=""; filename=""; nofn=""
				eval ${ln#*;}
				if echo $ln | grep -qv filename=; then nofn=1; fi
				#echo name="$name" filename="$filename no_filename=$nofn"
			elif test -z "$ln"; then # msg body. Ignore possible Content-Type
				if test -n "$name"; then
					cat > /tmp/$name
					rm $i
					#strip file last CR/LF, sed '$d', will delete whole last line
					flen=$(stat -c %s /tmp/$name)
					dd if=/tmp/$name of=/tmp/$name bs=1 seek=$((flen - 2)) count=0 >& /dev/null
					# if it is a text form, define a variable with it
					if test -n "$nofn"; then
						eval $name='$(cat /tmp/$name)'
						#echo "-------->$name: $(eval echo \"\$$name\")"
						fname_ret="$fname_ret $name='$(eval echo \"\$$name\")'"
						rm /tmp/$name
					else
						fname_ret="$fname_ret $name='/tmp/$name'"
					fi
					break
				fi
			fi
			if test $((++lncnt)) -gt 20; then
				cat > /dev/null # discard transfer
				rm -f $files
				echo "upload_file_inner:  sync lost?"
				return 1
			fi
		done < $i
	done
	umask $oumask
	echo "$fname_ret"
}

# to use on enctype=multipart/data forms.
# uploads every form elements as files and returns
# file1=name1, file2=name2, var1=value1, var2=value1,...
# files or variables might be empty
# variables are used when filename= does not appears in Content-Disposition
# for files, the filename= value is ignored, files are saved with name as name=
# Content-type is ignored
#
upload_file() {
# POST upload format:
# -----------------------------29995809218093749221856446032^M
# Content-Disposition: form-data; name="file1"; filename="..."^M
# Content-Type: application/octet-stream^M <-- optional
# ^M    <--------- headers end with empty line
# file contents
# file contents
# file contents
# ^M    <--------- extra empty line
# -----------------------------29995809218093749221856446032--^M
#
# CONTENT_TYPE and CONTENT_LENGTH are in cgi environment

	local reqm xxupfile lines
	if ! echo "$CONTENT_TYPE" | grep -q multipart/form-data; then
			cat > /dev/null # discard transfer
			echo "No Content_type: multipart/form-data on response."
			return 1
	fi
	
	eval $(df -m /tmp | awk '/tmpfs/{printf "totalm=%d; freem=%d;", $2, $4}')
	reqm=$((CONTENT_LENGTH * 2 / 1024 / 1024))
	if test "$reqm" -gt "$freem"; then
		if ! mount -o remount,size=$((totalm + reqm + 10 - freem))M /tmp; then
			cat > /dev/null # discard transfer
			echo "Not enought /tmp memory,\n$reqm MB required, $freem MB available.\nIs swap active?"
			return 1
		fi
	fi

	xxupfile=$(mktemp)
	cat > $xxupfile
	
	eval echo $CONTENT_TYPE >& /dev/null
	lines=$(grep -n -- $boundary $xxupfile | cut -d: -f1)
	
	upload_file_inner $lines
}


# end of FIXME to remove after 1.1

cert_bits() {
	if test "$1" -ge 1024; then
		SSL_CERT_TYPE="rsa"
		SSL_CERT_ARGS="-newkey $SSL_CERT_TYPE"
	else
		SSL_CERT_TYPE="ec"
		SSL_CERT_T="-newkey $SSL_CERT_TYPE"
		case "$1" in
			224) SSL_CERT_ARGS="$SSL_CERT_T -pkeyopt ec_paramgen_curve:secp224r1" ;;
			256) SSL_CERT_ARGS="$SSL_CERT_T -pkeyopt ec_paramgen_curve:prime256v1" ;;
			384) SSL_CERT_ARGS="$SSL_CERT_T -pkeyopt ec_paramgen_curve:secp384r1" ;;
		esac
	fi
}

le_args() {
	case $nbits_le in
		256|384) LE_KEYLEN="ec-$nbits_le"; LE_ARG=--ecc; LE_SUF="_ecc"; LE_KEY_T=ECC ;;
		2048|3072|4096) LE_KEYLEN=$nbits_le; LE_KEY_T=RSA ;;
		224|1024) msg "Let's Encrypt does not issue $nbits_le bits certificates." ;;
	esac
}

# PORT_CHECKER=https://www.canyouseeme.org	
# $1-external port
# canyouseeme_slower() {
# 	if test "$1" -gt 0; then
# 		ok_res='color="green"><b>Success:</b>'
# 		#err_res='color="red"><b>Error:</b>'
# 		if wget -q --post-data port=$1 -O - $PORT_CHECKER | grep -q "$ok_res"; then
# 			return 0
# 		fi
# 	fi
# 	return 1
# }

# $1-external port
canyouseeme() {
	if test -n "$1"; then
		PROTO=http
		if test $1 = 443; then PROTO=https; fi
		if wget -q $PROTO://$ext_domain --no-check-certificate -O /dev/null; then
			return 0
		fi
	fi
	return 1
}

#umask 077

if test "${CONTENT_TYPE%;*}" = "multipart/form-data"; then
	if ! res=$(upload_file); then
		msg "Error: Uploading failed."
	fi
	#echo res="$res"
	eval "$res"
else
	read_args
fi

#debug
#enddebug
#exit 1

if test -n "$ProtectKey"; then
	if test -z "$pass1"; then
		msg "The password can't be empty."
	elif test "$pass1" != "$pass2"; then
		msg "The two passwords don't match."
	fi

	if ! pass1=$(checkpass "$pass1"); then
    	msg "$pass1"
	fi
	
	cert_bits $nbits_ca
	
	echo "$pass1" | openssl $SSL_CERT_TYPE -des3 -in $BOX_CA_KEY \
		-out $BOX_CA_KEY-tmp -passout stdin >& /dev/null
	mv $BOX_CA_KEY-tmp $BOX_CA_KEY	

elif test -n "$CRTexport"; then
	download_file $BOX_CA_CRT ShareOS-fake-rootCA.crt
	exit 0

elif test -n "$CAsave"; then
	cat $BOX_CA_KEY $BOX_CA_CRT > $BOX_CA_PEM
	download_file $BOX_CA_PEM ShareOS-fake-rootCA.pem
	rm $BOX_CA_PEM
	exit 0
	
elif test -n "$CAload"; then
	if test -z "$pass"; then
		rm -f $CAload2
		msg "Error, you have to supply the password of the file private key to load."
	fi
	
	if ! pass=$(checkpass "$pass"); then
		rm -f $CAload2
    	msg "$pass"
	fi
	
	if ! test -s $CAload2; then
		rm -f $CAload2
		msg "Error, empty file uploaded."
	fi
	
	mv $CAload2 $BOX_CA_PEM
	sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' $BOX_CA_PEM > $BOX_CA_CRT-tmp
	sed -n '/BEGIN .*PRIVATE KEY/,/END .*PRIVATE KEY/p' $BOX_CA_PEM > $BOX_CA_KEY-tmp
	rm -f $BOX_CA_PEM

	if ! test -s $BOX_CA_KEY-tmp -a -s $BOX_CA_KEY-tmp; then
		rm -f $BOX_CA_KEY-tmp $BOX_CA_CRT-tmp
		msg "Error, the key and certificate, in DEM format, must be concatenated together in the file to upload."
	fi
	
	eval $(openssl x509 -in $BOX_CA_CRT-tmp -noout -text 2>/dev/null | 
		sed -n 's/.*(\(.*\) bit)/bits="\1"/p')
	
	cert_bits $bits
	
	# verify key consistency
	if ! echo -n "$pass" | openssl $SSL_CERT_TYPE -passin stdin -in $BOX_CA_KEY-tmp \
		-check -noout >& /dev/null; then
			rm -f $BOX_CA_KEY-tmp $BOX_CA_CRT-tmp
			msg "Error, wrong key password or private key is inconsistent."
	fi

# Another way to check the private key and cert pub key, is to sign a message
# with the private key and then verify it with the public key. You could do it like this:
# openssl x509 -in [certificate] -noout -pubkey > pubkey.pem
# dd if=/dev/urandom of=rnd bs=32 count=1
# openssl rsautl -sign -pkcs -inkey [privatekey] -in rnd -out sig
# openssl rsautl -verify -pkcs -pubin -inkey pubkey.pem -in sig -out check
# cmp rnd check
# rm rnd check sig pubkey.pem
# https://blog.hboeck.de/archives/888-How-I-tricked-Symantec-with-a-Fake-Private-Key.html

	# verify public keys are identical in cert and key
	crtck=$(openssl x509 -in $BOX_CA_CRT-tmp -pubkey | \
		openssl pkey -pubin -pubout -outform der | sha256sum)
	
	keyck=$(echo "$pass" | openssl pkey -passin stdin -in $BOX_CA_KEY-tmp \
		-pubout -outform der | sha256sum)
	
	if ! test "$crtck" = "$keyck"; then		
		rm -f $BOX_CA_KEY-tmp $BOX_CA_CRT-tmp
		msg "Error, key and certificate public keys don't match."
	fi

	mv $BOX_CA_KEY-tmp $BOX_CA_KEY
	mv $BOX_CA_CRT-tmp $BOX_CA_CRT
	chmod a+r $BOX_CA_CRT
	chmod og-rw $BOX_CA_KEY

elif test -n "$createCA"; then

	SSL_CERT_BITS=$nbits_ca
	sed -i '/^SSL_CERT_BITS=/d' $MISC_CONF
	echo "SSL_CERT_BITS=\"$SSL_CERT_BITS\"" >> $MISC_CONF
	
	cert_bits $nbits_ca
	
	html_header "Creating a $SSL_CERT_BITS bits $SSL_CERT_TYPE certificate as the ShareOS fake root CA..."
	busy_cursor_start
	sleep 1
	
	export HOST=$(hostname) HOSTFQDN=$(hostname -f) HOSTIP=$(hostname -i) \
		DOMAIN=$(hostname -d) BOX=$(cat /tmp/board) REQNAME=req_dname_ca SSL_CERT_BITS
		
	openssl req -x509 -new -nodes -sha256 -days 7300 $SSL_CERT_ARGS -keyout $BOX_CA_KEY \
		-out $BOX_CA_CRT -extensions v3_ca -config $BOX_CNF >& /dev/null

	chmod og-w $BOX_CA_KEY $BOX_CA_CRT
	chmod og-rw $BOX_CA_KEY
	
	busy_cursor_end
	
elif test -n "$createCert"; then
	if test -z "$pass"; then
		msg "Error, you have to supply the password of the CA private key."
	fi
	
	if ! pass=$(checkpass "$pass"); then
    	msg "$pass"
	fi
	
#	if test -z "$SSL_CERT_BITS"; then
#		SSL_CERT_BITS=256
#		sed -i '/^SSL_CERT_BITS=/d' $MISC_CONF
#		echo "SSL_CERT_BITS=\"$SSL_CERT_BITS\"" >> $MISC_CONF
#	fi
	
	cert_bits $nbits_cert
	
	html_header "Creating a $nbits_cert bits $SSL_CERT_TYPE certificate signed with the ShareOS fake root CA..."
	busy_cursor_start
	sleep 1
	
	# first remove other services certificates if they are identical to the current one
	for i in pem crt key; do
		for j in $SSL_DIR/*.$i; do
			if test $(basename $j .$i) != "server" && cmp -s $j $SSL_DIR/server.$i; then rm $j; fi
		done
	done
	
	export HOST=$(hostname) HOSTFQDN=$(hostname -f) HOSTIP=$(hostname -i) \
		DOMAIN=$(hostname -d) BOX=$(cat /tmp/board) REQNAME=req_dname SSL_CERT_BITS=$nbits_cert

	rm -f $BOX_KEY $BOX_CRT $BOX_PEM
	
	# create box private key and sign request in one step
	openssl req -new -nodes -sha256 $SSL_CERT_ARGS \
		-keyout $BOX_KEY -out $BOX_CSR -config $BOX_CNF >& /dev/null

	# CA sign the certificate sign request
	echo "$pass" | openssl x509 -req -days 365 -sha256 \
		-CA $BOX_CA_CRT -CAkey $BOX_CA_KEY -CAcreateserial -passin stdin \
		-in $BOX_CSR -out $BOX_CRT -extensions v3_req -extfile $BOX_CNF >& /dev/null
	cat $BOX_KEY $BOX_CRT > $BOX_PEM
	
	chmod og-w $BOX_CRT $BOX_KEY
	chmod og-rw $BOX_PEM $BOX_KEY
	
	# FIXME: servers that use the old certificate should be restarted and their certificates recreate
	SSL_SVC="vsftpd stunnel cups lighttpd mysqld"
	for i in $SSL_SVC; do
		if test -x /sbin/rc${i}; then rc${i} init; fi
	done
	rcstunnel reload >& /dev/null # FIXME: browser complains cert changed, has to reload page

	busy_cursor_end
	
elif test -n "$selfSignCert"; then # FIXME: see the above FIXME
# 	if test -z "$SSL_CERT_BITS"; then
# 		SSL_CERT_BITS=256
# 		sed -i '/^SSL_CERT_BITS=/d' $MISC_CONF
# 		echo "SSL_CERT_BITS=\"$SSL_CERT_BITS\"" >> $MISC_CONF
# 	fi
	
	cert_bits $nbits_cert
		
	html_header "Creating a $nbits_cert bits $SSL_CERT_TYPE self-signed box certificate..."
	busy_cursor_start
	sleep 1
	
	rm -f $BOX_KEY $BOX_CRT $BOX_PEM

	export HOST=$(hostname) HOSTFQDN=$(hostname -f) HOSTIP=$(hostname -i) \
		DOMAIN=$(hostname -d) BOX=$(cat /tmp/board) REQNAME=req_dname SSL_CERT_BITS=$nbits_cert

	# create box private key and cert and selfsign in one step
	openssl req -x509 -nodes -sha256 -days 365 $SSL_CERT_ARGS \
		-keyout $BOX_KEY -out $BOX_CRT -extensions v3_req -config $BOX_CNF >& /dev/null
	cat $BOX_KEY $BOX_CRT > $BOX_PEM
	
	# FIXME: servers that use the old certificate should be restarted and their certificates recreate
	SSL_SVC="vsftpd stunnel cups lighttpd mysqld"
	for i in $SSL_SVC; do
		if test -x /sbin/rc${i}; then rc${i} init; fi
	done

	rcstunnel reload >& /dev/null # FIXME: browser complains cert changed, has to reload page

	busy_cursor_end

elif test -n "$getCert"; then
	le_args

	html_header "Requesting a $nbits_le bits $LE_KEY_T certificate from Let's Encrypt"
	busy_cursor_start
	
	use_lighty=yes # use lighttpd in acme.sh webroot or alpn dir mode

	ACME_ARGS="$ACME_MODE --issue
		--domain $ext_domain
		--keylength $LE_KEYLEN
		--cert-file $INST_DIR/$ext_domain.crt
		--key-file $INST_DIR/$ext_domain.key
		--ca-file $INST_DIR/$ext_domain-ca.crt"
	# can't put reloadcmd or hooks in variable as they contain strings
	# and acme.sh parses positional arguments
	
	err_msg="Error obtaining certificate from Let's Encrypt, for details see the acme.sh log."

	server_root=$(httpd -d $server_root)
	alpndir=$(httpd -d $alpndir)
	http_port=$(httpd -d $http_port)
	https_port=$(httpd -d $https_port)
		
	# double "$@" expansion in /usr/bin/acme.sh and acme.sh itself is not working... repeat
	if canyouseeme 80 >& /dev/null; then
		echo "<p><strong>Port 80 visible from the internet, requesting certificate:</strong></p><pre>"

		if test "$use_lighty" = yes; then
			if ! acme.sh $ACME_ARGS --webroot $server_root/htdocs \
				--reloadcmd "rclighttpd restart"; then
				msg "$err_msg"
			fi
		else
			if ! acme.sh $ACME_ARGS --standalone --httpport $http_port \
				--pre-hook "rclighttpd sstop" --post-hook "rclighttpd start"; then
				msg "$err_msg"
			fi
		fi
	elif canyouseeme 443 >& /dev/null; then
		echo "<p><strong>Port 443 visible from the internet, requesting certificate:</strong></p><pre>"
		
		if test "$use_lighty" = yes; then
			if ! acme.sh $ACME_ARGS --alpn $alpndir \
				--reloadcmd "rclighttpd restart"; then
				msg "$err_msg"
			fi
		else
			if ! acme.sh $ACME_ARGS --alpn --tlsport $https_port \
				--pre-hook "rclighttpd sstop" --post-hook "rclighttpd start"; then
				msg "$err_msg"
			fi
		fi
	else
		msg "Neither external port 80 nor port 443 can be seen from the internet. Check the router port forwarding on the lighttpd configuration."
	fi
	
	MAIL_FROM=$(httpd -d "$MAIL_FROM")
	MAIL_TO=$(httpd -d "$MAIL_TO")
	export MAIL_FROM MAIL_TO MAIL_BIN="/usr/bin/mail"
	
	echo "</pre><p><strong>Got certificate, now setting notify e-mail address and renew cronjob:</strong></p><pre>"
	if ! acme.sh $ACME_MODE --set-notify --notify-hook mail; then
		msg "acme.sh set notify error, for details see the acme.sh log."
	fi

	acme.sh --install-cronjob
	
	busy_cursor_end
	echo "</pre><p><strong>Sucess</strong> $(goto_button Continue /cgi-bin/certs.cgi)</p></body></html>"
	exit 0

elif test -n "$renewCert"; then
	le_args
	html_header "Renewing Let's Encrypt certificate"
	busy_cursor_start
	
	echo "<pre>"
	if ! acme.sh $ACME_MODE --renew --force --domain $ext_domain $LE_ARG; then
		msg "Error renewing certificate, for details see the acme.sh log."
	fi
	
	busy_cursor_end
	echo "</pre><p><strong>Sucess</strong> $(goto_button Continue /cgi-bin/certs.cgi)</p></body></html>"
	exit 0

elif test -n "$revokeCert"; then
	le_args
	html_header "Revoking Let's Encrypt certificate"
	busy_cursor_start

	echo "<pre>"
	if ! acme.sh $ACME_MODE --revoke --domain $ext_domain $LE_ARG; then
		msg "Error revoking certificate, for details see the acme.sh log."
	fi
	
	rm -rf $ACME_CONF/${ext_domain}$LE_SUF $INST_DIR/${ext_domain}*
	
	# lighty is most certainly using the cert:
	if grep -q $ext_domain $CONF_LIGHTY; then
		# using intranet cert for Lets Encript tls-alpn handshake.
		# use cp not ln, as acme.sh uses cat to preserve perms.
		cp $INST_DIR/server.crt $INST_DIR/$ext_domain.crt
		cp $INST_DIR/server.key $INST_DIR/$ext_domain.key
		#cp $INST_DIR/server.pem $INST_DIR/$ext_domain.pem
		cp $INST_DIR/rootCA.crt $INST_DIR/$ext_domain-ca.crt # hack
	fi

	acme.sh --uninstall-cronjob
	
	busy_cursor_end
	echo "</pre><p><strong>Sucess</strong> $(goto_button Continue /cgi-bin/certs.cgi)</p></body></html>"
	exit 0

	
elif test -n "$removeCert"; then
	le_args
	busy_cursor_start

	if ! acme.sh $ACME_MODE --remove --domain $ext_domain $LE_ARG >& /dev/null; then
		msg "Error removing certificate, for details see the acme.sh log."
	fi

	rm -rf $ACME_CONF/${ext_domain}$LE_SUF $INST_DIR/${ext_domain}*
	
	# lighty is most certainly using the cert:
	if grep -q $ext_domain $CONF_LIGHTY; then
		# using intranet cert for Lets Encript tls-alpn handshake.
		# use cp not ln, as acme.sh uses cat to preserve perms.
		cp $INST_DIR/server.crt $INST_DIR/$ext_domain.crt
		cp $INST_DIR/server.key $INST_DIR/$ext_domain.key
		#cp $INST_DIR/server.pem $INST_DIR/$ext_domain.pem
		cp $INST_DIR/rootCA.crt $INST_DIR/$ext_domain-ca.crt # hack
	fi
	
	acme.sh --uninstall-cronjob
fi

#enddebug
js_gotopage /cgi-bin/certs.cgi
