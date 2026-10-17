#!/bin/sh

. common.sh
check_cookie
read_args

#debug

CONFP=/etc/passwd
CONFG=/etc/group
CONFS=/etc/samba/smbusers
CONFR=/etc/rsyncd.conf
CONFRS=/etc/rsyncd.secrets

if test -n gname; then
	gname=$(httpd -d "$gname")
fi

if test -n "$new_user"; then
	gotopage /cgi-bin/newuser.cgi?act=newuser

elif test -n "$user_quota"; then
	gotopage /cgi-bin/quota.cgi?user=$nick

elif test -n "$grp_quota"; then
	gotopage /cgi-bin/quota.cgi?group=$gname

elif test -n "$change_pass"; then
	gotopage /cgi-bin/newuser.cgi?act=changepass?uname=$uname?nick=$nick

elif test -n "$del_user"; then
	if id $nick >& /dev/null; then
		udir=$(awk -F : '/^'$nick':/{print $6}' $CONFP)
		uname=$(awk -F : '/^'$nick':/{print $5}' $CONFP)
		smbpasswd -x $nick >& /dev/null
		rm -f /etc/samba/credentials.$nick
		sed -i "/^$nick = /d" $CONFS >& /dev/null
		sed -i -e "/^$nick:/d" -e "/^$uname:/d" $CONFRS  >& /dev/null
		sed -i -e "/^\[$nick\]/,/^$/d" -e "/^\[$uname\]/,/^$/d" $CONFR >& /dev/null

		for i in $(id -Gn $nick); do
			delgroup $nick $i >& /dev/null
		done
		deluser $nick >& /dev/null

		if test -d "$udir"; then
			if ! rmdir "$udir" >& /dev/null; then
				msg "The users home folder is not empty and was not deleted"
			fi
		fi
	fi

elif test -n "$new_group"; then
	if test $(eatspaces $gname) != "$gname"; then
		msg "Group name must not contain spaces"
	fi
	eval $(awk -F : '{if ($3 > mg) mg=$3} END{printf "ggid=%d", mg+1}' $CONFG)
	res=$(addgroup -g $ggid "$gname" 2>&1)
	if test $? != 0; then
		msg "Can't create group $gname: $res"
	fi

elif test -n "$del_group"; then
	if test $(eatspaces $gname) != "$gname"; then
		msg "Group name must not contain spaces"
	fi
	gid=$(awk -F: -v gname=$gname '$1 == gname {print $3}' $CONFG)
	ug="$(awk -F: -v gid=$gid '$4 == gid {print $1}' $CONFP)"
	if test -n "$ug"; then
		msg "This group is the main group of several users, can't delete it"
	fi
	delgroup "$gname"

elif test -n "$addToGroup"; then
	addgroup $nick "$gname"

elif test -n "$delFromGroup"; then
	# delgroup $nick $gname # not working, busybox bug
	sed -i  -e '/^'$gname':/s/,'$nick'$//'  \
		-e '/^'$gname':/s/:'$nick',/:/' \
		-e '/^'$gname':/s/,'$nick',/,/' \
		-e '/^'$gname':/s/:'$nick'$/:/'  \
		$CONFG
fi

gotopage /cgi-bin/usersgroups.cgi

#enddebug
