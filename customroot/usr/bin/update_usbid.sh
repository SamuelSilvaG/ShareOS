#!/bin/sh

USBID="usb.ids"
USBIDC=$USBID.gz
USBID_SITE="http://www.linux-usb.org/$USBIDC"

ok() {
	echo "$0: $1"
	rm -f $USBIDC.bck $TF
	exit 0
}

error() {
	echo "$0: $1"
	rm -f $TF $USBID.new
	mv $USBIDC.bck $USBIDC
	gunzip -c $USBIDC > $USBID
	exit 1
}

cd /usr/share
cp -p $USBIDC $USBIDC.bck
TF=$(mktemp)
touch -r $USBIDC $TF

if ! wget -qN $USBID_SITE; then
	err "download failed."
fi

if ! test $USBIDC -nt $TF; then
	ok "nochange."
fi

if ! gunzip -t $USBIDC; then
	err "source or download corrupted."
fi

if ! gunzip -c $USBIDC > $USBID.new; then
	err "uncompression failed."
fi

mv $USBID.new $USBID
ok "updated."

