#!/bin/sh

. common.sh
check_cookie
read_args

MY_CONF=/etc/mysql/my.cnf

#debug

if test -n "$rmTestDB"; then
	mysql -Be "drop database if exists test;
	delete from mysql.db where db='test' or db='test\\_%';"
	
elif test -n "$removeAnon"; then
	mysql -Be "delete from mysql.user where user=''"

elif test -n "$setPassword"; then
	pass=$(httpd -d "$pass")
	mysql -Be "update mysql.user set password = PASSWORD('"$pass"') where user='root';
	flush privileges;"
	sed -i 's/^[#[:space:]]*password[[:space:]]*=.*$/password\t= '$pass'/' $MY_CONF
	chmod og-r $MY_CONF

elif test -n "$enableRemoteRoot"; then
# duplicate root user to accept IP or wildcard (%) remote host connections
# using a IP is off by one, and using a FQDN hostname is not working (because of the IP bug?)
cat <<-EOF | mysql -B
	use mysql;
	create temporary table temp_table select * from user
		where user='root' and host='localhost';
	#update temp_table set host='192.168.1.73'; # use IP or IP/netmask
	#update temp_table set host='yoga.homenet'; # use host name *as* shown in nslookup
	update temp_table set host='%'; # allow all remote connections
	insert into user select * from temp_table;
	drop temporary table temp_table;
	flush privileges
EOF

elif test -n "$disableRemoteRoot"; then
	mysql -Be "delete from mysql.user where user='root' and host='%'; flush privileges"
	
elif test -n "$enableSSL"; then
	sed -i 's/^#ssl_\(.*\)$/ssl_\1/' $MY_CONF
	rcmysqld restart >& /dev/null

elif test -n "$disableSSL"; then
	sed -i 's/^ssl_\(.*\)$/#ssl_\1/' $MY_CONF
	rcmysqld restart >& /dev/null
	
elif test -n "$removeUser"; then
	removeUser=$(httpd -d $removeUser)
	user=$(echo "$removeUser" | cut -d@ -f1)
	host=$(echo "$removeUser" | cut -d@ -f2)
	
	if test -z "$host" -o "$host" = "$user"; then host="localhost"; fi
	
	if test -n "$user" -a "$user" != "root"; then
		mysql -Be "drop user '$user'@'$host'"
	fi

elif test -n "$disable"; then
	disable=$(httpd -d $disable)
	dbname=$(echo "$disable" | cut -d@ -f1)
	user=$(echo "$disable" | cut -d@ -f2)
	host=$(echo "$disable" | cut -d@ -f3)
	
	if test -n "$user" -a "$user" != "root"; then
		mysql -Be "revoke all privileges on \`$dbname\`.* from '$user'@'$host'"
	fi

elif test -n "$dropDB"; then
	dropDB=$(httpd -d $dropDB)
	if test -n "$dropDB" -a "$dropDB" != "mysql"; then
		mysql -Be "drop database \`$dropDB\`"
	fi
	
elif test -n "$createDB"; then
	dbname=$(trimspaces $(httpd -d "$dbname"))
	dbuserDB=$(trimspaces $(httpd -d "$dbuserDB"))
	user=$(echo "$dbuserDB" | cut -d@ -f1)
	host=$(echo "$dbuserDB" | cut -d@ -f2)
	
	if test -z "$host" -o "$host" = "$user"; then host="localhost"; fi
	
	grantcmd="grant all privileges on \`$dbname\`.* to '$user'@'$host'"
	if test -z "$user" -o "$user" = "root"; then
		grantcmd=
	fi
	
	if test -n "$dbname"; then
		mysql -Be "create database if not exists \`$dbname\`; $grantcmd"
	fi
	
elif test -n "$createUser"; then
	dbuser=$(trimspaces $(httpd -d "$dbuser"))
	dbwhere=$(trimspaces $(httpd -d "$dbwhere"))
	dbpass=$(trimspaces $(httpd -d "$dbpass"))
	
	if test "$dbuser" = "root"; then dbuser=""; fi
	if test -z "$dbwhere"; then dbwhere="localhost"
	elif test "$dbwhere" = "any-host"; then dbwhere="%"
	fi
	
	if test -n "$dbuser"; then
		if test -n "$(mysql -NBe "select user from mysql.user where user='$dbuser' and host='$dbwhere'")"; then
			mysql -Be "update mysql.user set password=password('$dbpass') where user='$dbuser' and host='$dbwhere'"
		else
			mysql -Be "create user '$dbuser'@'$dbwhere' identified by '$dbpass'"
		fi
	fi
fi

#enddebug
gotopage /cgi-bin/mysqld.cgi

