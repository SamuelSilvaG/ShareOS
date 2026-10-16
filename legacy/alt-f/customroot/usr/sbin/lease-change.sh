#!/bin/sh

# script that dnsmasq calls when leases change.
#
# adds/removes the host name appended with .local into /etc/hosts, as a name alias,
# allowing dnsmasq (and all served hosts without mDNS) to resolve mDNS hosts
# in the .local fake domain.

save_hdate() {
	TF=$(mktemp)
	touch -r /etc/hosts $TF
	sed -i "/$hname.local/d" /etc/hosts
}

load_hdate() {
	touch -r $TF /etc/hosts
	rm $TF
}

exec 2>&1 >> /var/log/lease-change.log

echo "$(date +'%F %T'): args: $@"
#echo env:$(env)
#echo set:$(set)

type=$1
MAC=$2
IP=$3
hname=$4

if test "$type" = "old" -a -z "$hname"; then
	hname="$DNSMASQ_OLD_HOSTNAME"
fi

if test -z "$hname"; then
	echo "no host name, no action taken"
	return
fi

case $type in
	old|add)
		save_hdate

		if test -n "$DNSMASQ_DOMAIN"; then
			echo -e "$IP\t$hname.$DNSMASQ_DOMAIN\t$hname.local\t$hname" >> /etc/hosts
		else
			echo -e "$IP\t$hname\t$hname.local" >> /etc/hosts
		fi
		load_hdate
		;;
	del)
		save_hdate
		load_hdate
		;;
	*)	echo "unknown $type action, no action taken"
		;;
esac
