#!/bin/sh

. common.sh
check_cookie

write_header "MySQL Setup"

MY_CONF=/etc/mysql/my.cnf
SERRORL=/var/log/systemerror.log
CONFF=/etc/misc.conf

if ! rcmysqld status >& /dev/null; then
	rcmysqld start >& /dev/null
fi

if ! mysql -Be "" >& /dev/null; then
	echo "<p class=\"error\">Can't continue, there is no password stored in the configuration file or it is incorrect.</p></body></html>"
	exit 0
fi

pass=$(sed -n 's/^[[:space:]]*password[[:space:]]*=[[:space:]]*\(.*\)/\1/p' $MY_CONF)

if test -n "$pass"; then
	passmsg="Change mysql root password"
	passval="changePassword"
	emsg="<li>Assign a password to your mysqld root user.</li>"
	sed -i '\|'"$emsg"'|d' $SERRORL 2> /dev/null
else
	passmsg="<span class=\"red\">Set mysql root password</span>"
	passval="setPassword"
fi

if test -z "$(mysql -Be "select user,host from mysql.user where user='root' and host='%'")"; then
	remoteroot="<p>Allow all remote connections for root
	<input type=submit name=enableRemoteRoot value=\"enableRemoteRoot\"</p>"
else
	remoteroot="<p class=\"red\">Disable remote connections for root
	<input type=submit name=disableRemoteRoot value=\"disableRemoteRoot\"</p>"
fi

if ! grep -qE '^ssl_(ca|cert|key)' $MY_CONF; then
	encrypt="<p class=\"red\">Enable encrypted connections <input type=submit name=enSSL value=\"enableSSL\"></p>"
else
	encrypt="<p>Disable encrypted connections <input type=submit name=enSSL value=\"disableSSL\"></p>"
fi

if test -n "$(mysql -BNe "select user,host from mysql.user where user=''")"; then
	anonmsg="<p class=\"red\">Remove anonymous user
	<input type=submit name=removeAnon value=\"removeAnon\"></p>"
fi

if test -n "$(mysql -BNe "show databases like 'test'")"; then
	testdb="<p class=\"red\">Remove test database
	<input type=submit name=rmTestDB value=\"removeTest\"></p>"
fi

cat <<-EOF
	<form name=mysqld action=mysqld_proc.cgi method="post">
	
	<fieldset><legend>Secure Mysql</legend>
	<p>$passmsg: <input type=password name="pass" value="$pass">
	 <input type=submit name=setPassword value="$passval">
	</p>
	$remoteroot
	$anonmsg
	$testdb
	$encrypt
	</fieldset>
	
 	<fieldset><legend>Databases</legend>
 	<table>
 	<tr><th>Database</th><th></th><th>Owned by</th></tr>
EOF

	db=$(mysql -BNe "show databases" | grep -vwE "information_schema|mysql|test")

if test -n "$db"; then
	echo "$db" | while read ln; do
		users=$(mysql -tNe "select user,host from mysql.db where db='$ln'" | \
		awk -v db="$ln" -F\| '/^\|/ {
		gsub(/^ *| *$/, "",$2); gsub(/^ *| *$/, "", $3);
		if (length($2) == 0 || $2 == "root") return
		if ($3 == "%") $3 = "any-host"
		printf("<td>%s@%s</td><td><input type=submit name=\"%s@%s@%s\" value=\"disable\"></td> ", $2, $3, db, $2, $3)}')
		echo "<tr><td>$ln</td><td><input type=submit name=\"$ln\" value="dropDB">$users<td></tr>"
	done
fi
	
cat <<-EOF
	</table>

	<p>Create database <input type=text name=dbname value="">
	for user (or allow user) <input type=text name=dbuserDB value="">
	<input type=submit name=createDB value="createDB"></p>

	</fieldset>
	
	<fieldset><legend>Users</legend>
	<table>
	<tr><th>User</th><th>Password</th></tr>
EOF

mysql -tNe 'select user,host,password from mysql.user' | awk -F\| '/^\|/{
	gsub(/^ *| *$/, "",$2); gsub(/^ *| *$/, "", $3); gsub(/^ *| *$/, "", $4)
		if (length($2) == 0 || $2 == "root") return
		if ($3 == "%") host = "any-host"; else host = $3
		if (length($4) == 0) $4 = "<span class=warn>none</span>"; else $4="OK"
		printf("<tr><td>%s@%s</td><td>%s</td><td><input type=submit name=\"'%s'@'%s'\" value=\"removeUser\"></td></tr>", $2, host, $4, $2, $3)}'

cat<<-EOF
	</table>

	<p>Create user <input type=text name=dbuser value="">
	for host <input type=text name=dbwhere value="">
	with password (or change password) <input type=password name=dbpass value="">
	<input type=submit name=createUser value="createUser"></p>

	</fieldset>
	
	<p><input type=submit value=Submit>$(back_button)
	</form></body></html>
EOF
