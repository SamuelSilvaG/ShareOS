#!/bin/sh

. common.sh
check_cookie
write_header "Cryptsetup Setup"

mktt crypt_tt "Location of file with the encrypt password.<br>
Should be on removable USB medium, not on the<br>
same disk or box as the encrypted filesystem.<br>
Only needed when formating or opening."

mktt cipher_tt "aes-cbc-essiv:sha256 is faster because it is hardware accelerated and is considered sufficient.<br>
aes-xts-plain64:sha256 is slower but stronger.<br>
other cipher specification might be accepted, depending on its values, see<br>
https://superuser.com/questions/775200/how-do-i-determine-what-ciphers-cipher-modes-i-can-use-in-dm-crypt-luks"

mktt cesa_tt "Using the hardware accelerator engine increases performance"

CONF_MISC=/etc/misc.conf
CONF_MOD=/etc/modules

. $CONF_MISC

if grep -q ^marvell_cesa $CONF_MOD; then
	cesa_chk=checked
fi

rccryptsetup load >& /dev/null

# top level devices, i.e., not holded by any other device
devs=""
for i in /sys/block/sd[a-z]/sd[a-z][0-9]/holders \
	/sys/block/md[0-9]*/holders \
	/sys/block/dm-[0-9]*/holders; do
	dev=$(basename $(dirname $i))
	if cryptsetup status /dev/$dev >& /dev/null; then continue; fi
	if test -z "$(ls -A $i 2> /dev/null)"; then devs="$devs|$dev"; fi
done
 
if test -n "$devs"; then
	devs="$(awk '/'${devs:1}'/{
		dm=$4; "cat /sys/block/"$4"/dm/name 2> /dev/null" | getline dm;
		printf "<option value=%s>%s (%.1f GB)</option>\n",
 		$4, dm, $3*1024/1e9}' /proc/partitions)"
fi

cat<<EOF
	<form id="cryptf" action="/cgi-bin/cryptsetup_proc.cgi" method="post">
	<fieldset><legend>Encrypt</legend>
	<table><tr><th>Device</th><th>Cipher Mode</th><th>Bits</th><th></td></tr>
	<tr><td><select name=devto><option value=none>Select a Device</option>$devs</select></td>
		<td><input type=text name=cipher value="aes-cbc-essiv:sha256" $(ttip cipher_tt)></td>
		<td><select name=nbits><option>128</option><option>192</option><option selected>256</option></select></td>
		<td><input type="submit" name=action value="Format" onClick="return confirm('All data in the selected device will be lost.\n\nProceed?')"></td></tr>
	</table></fieldset>
EOF

curr=$(blkid -t TYPE=crypt_LUKS -o device -c /dev/null)
raiddevs=$(mdadm --detail /dev/md[0-9]* 2> /dev/null | awk  '/active sync/ {print $7}')
action="none"
# or curr=$(echo $raiddevs $curr | tr ' ' '\n' | sort | uniq -u)

if test -n "$curr"; then
	cat<<-EOF
		<fieldset><legend>Encrypted devices</legend>
		<table><tr><th>Dev</th><th>Size (GB)</th><th>Cipher Mode</th>
		<th>Bits</th><th>State</th></tr>
	EOF
	for i in $curr; do
		if echo $i | grep -qE '_mlog|_mimage_|-real|-cow'; then continue; fi
		if ! cryptsetup isLuks $i >& /dev/null; then continue; fi
		# is a raid component of an active raid device? don't show
		if echo $raiddevs | grep -q $i; then continue; fi
	
		dev=$(basename $i); cdev=$dev
		if test -b /dev/mapper/$dev-crypt; then
			cdev=$dev-crypt
		fi
		
		if cst=$(cryptsetup status $cdev 2> /dev/null); then
			state="Active"
			action="Close"
			eval $(echo "$cst" | awk '
				/cipher:/ {printf "cipher=%s;", $2}
				/keysize:/ {printf "bits=%d;", $2}
				/size:/ {printf "sz=%.1f;", $2*512/1024/1024/1024}')
		else
			state="Inactive"
			action="Open"
			cipher=""; mode=""; bits=""
			eval $(cryptsetup luksDump $i | awk '
				/Cipher name/ {printf "cipher=%s;", $3} 
				/Cipher mode/ {printf "mode=%s;", $3} 
				/MK bits/ {printf "bits=%d;", $3}')
			cipher=$cipher-$mode
			
			cdev2=$dev
			if test -L $i; then cdev2=$(basename $(readlink $i)); fi
			sz=$(awk '/'$cdev2'/{printf "%.1f", $3 * 1024/1024/1024/1024}' /proc/partitions)	
		fi

		cat<<-EOF
		<tr><td>$cdev</td>
		<td align=right>$sz</td>
		<td align=center>$cipher</td>
		<td>$bits</td>
		<td><strong>$state</strong></td>
		<td><input type=submit name=$dev value="$action"></td>
		<td><input type=submit name=$dev value="Wipe" onClick="return confirm('All data in the device $dev will be lost.\n\nProceed?')"></td>
		</tr>
		EOF
	done

	echo "</table></fieldset>"
else
	rccryptsetup unload >& /dev/null
fi

cat<<-EOF
	<table>
	<tr><td>Use hardware accelerator</td><td><input type=checkbox $cesa_chk name=use_cesa value="yes" $(ttip cesa_tt)></td></tr>
	<tr><td>Password file:</td><td><input type=text name="keyfile" value="$CRYPT_KEYFILE" $(ttip crypt_tt)></td></tr>
	</table>
	<p><input type="submit" name=action value="Submit">$(back_button)
	</form></body></html>
EOF

