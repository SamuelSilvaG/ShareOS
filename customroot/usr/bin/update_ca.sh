#!/bin/sh

CA_PEM="cacert.pem"
CA_SHA="cacert.pem.sha256"
CA_SITE="https://curl.se/ca"

CA_BUNDLE="ca-bundle.crt"
ROOT_CA="certs/rootCA.crt"

ok() {
	logger -st $0 $1
	rm -f $TF $CA_PEM $CA_PEM.bck $CA_SHA.bck
	exit 0
}

err() {
	logger -st $0 $1
	mv $CA_PEM.bck $CA_PEM 
	mv $CA_SHA.bck $CA_SHA
	rm -f $TF $CA_PEM # remove link
	exit 1
}

cd /etc/ssl
ln -f $CA_BUNDLE $CA_PEM # handle name difference

TF=$(mktemp)
touch -r $CA_PEM $TF # get timestamp on reference file
cp -p $CA_PEM $CA_PEM.bck
cp -p $CA_SHA $CA_SHA.bck >& /dev/null 

wget -qN $CA_SITE/$CA_PEM $CA_SITE/$CA_SHA
st=$?
if test "$st" = 5; then
	if ! wget -qN --no-check-certificate $CA_SITE/$CA_PEM $CA_SITE/$CA_SHA; then
		err "download failed."
	fi
elif test "$st" != 0; then
	err "download failed."
fi

if ! test $CA_PEM -nt $TF; then
	ok "nochange."
fi

if ! sha256sum -s -c $CA_SHA; then
	err "sha256 check failed."
fi

# the Alt-F root CA cert must be added after a bundle update
if test -f $ROOT_CA; then
	if ! grep -q 'Alt-F root CA' $CA_BUNDLE; then
		echo -e "\nAlt-F root CA\n=============" >> $CA_BUNDLE
		cat $ROOT_CA >> $CA_BUNDLE
	fi
fi

ok "updated."

