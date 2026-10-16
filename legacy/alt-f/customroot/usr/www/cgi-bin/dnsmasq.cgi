#!/bin/sh

. common.sh
check_cookie
write_header "DHCP/DNS Setup"

CONF_H=/etc/dnsmasq-hosts
CONF_O=/etc/dnsmasq-opts
CONF_F=/etc/dnsmasq.conf
RESOLV=/etc/resolv.conf
CONFNTP=/etc/ntp.conf
CONFM=/etc/misc.conf
LEASES=/tmp/dnsmasq.leases

if ! test -e $CONF_H; then touch $CONF_H; fi

if test -f $CONFM; then
	. $CONFM
fi

hostip=$(hostname -i)
netmask=$(ifconfig eth0 | awk '/inet addr/ { print substr($4, 6) }')
hostnm=$(hostname -s)
hostfnm=$(hostname -f)
#eval $(ipcalc -ns $hostip $netmask)
#net=$(echo $NETWORK | cut -d. -f1-3)

eval $(awk -F"," '/dhcp-range=/{printf "lrg=%s; hrg=%s; lease=%s",
	 substr($1,12), $2, $3}' $CONF_F)

cat <<-EOF
	<script type="text/javascript">
	function toogle_ntp(st) {
		if (st == "true")
			stt = true
		else
			stt = false
		document.dnsmasq.ntp_entry.disabled = stt;
	}
	function toogle_tftp(theform) {
		st = document.dnsmasq.tftp.checked == true ? false : true
		document.dnsmasq.tftproot.disabled = st
		document.dnsmasq.ftpbrowse.disabled = st
	}
	function getMAC(mac_id, ip_id, nm_id) {
		ip = document.getElementById(ip_id).value
		nm = document.getElementById(nm_id).value
		window.open("get_mac.cgi?id=" + mac_id + "&ip=" + ip + "&nm=" + nm, "GetMAC", "width=300,height=120");
		return false
	}
	</script>

	<form name=dnsmasq action="/cgi-bin/dnsmasq_proc.cgi" method="post">
	<fieldset><legend>Dynamically serve IPs</legend><table>
	<tr><td> From IP</td><td><input type=text size=12 name=low_rg value="$lrg"></td></tr>
	<tr><td>To IP</td><td><input type=text size=12 name=high_rg value="$hrg"></td></tr>
	<tr><td>Lease Time: </td><td><input type=text size=4 name=glease value="$lease"></td></tr>
	</table></fieldset>
	<fieldset><legend>Current Leases</legend>
EOF

if ! test -s $LEASES; then
	echo "None"
else
	echo "<table><tr><th width=100px>Name</th><th width=100px>IP</th><th width=130px>MAC</th><th>Expiry date</th><th>Status</th></tr>"
	tf=$(mktemp)
	cp $LEASES $tf;
	sort -n $tf > $LEASES
	rm $tf
	while read exp mac ip name b; do
		dexp="$(awk 'BEGIN{print strftime("%b %d, %R",'$exp')}')"
		pidl="$pidl $ip"
		echo "<tr><td>$name</td><td>$ip</td><td>$mac</td><td>$dexp</td><td id=st_$ip></td></tr>"
	done < $LEASES
	echo "</table>"
fi
	
cat <<EOF
	</fieldset>
	<fieldset><legend>Assign a name and/or serve fixed IPs to a given MAC</legend>
	<table><tr align=center>
	<td> <strong> Name </strong> </td><td> <strong> IP </strong> </td><td> <strong> Get MAC </strong> </td>
	<td> <strong> MAC </strong> </td></tr>
EOF

oifs="$IFS"; IFS=","; cnt=0
while read mac nm ip lease rest; do
    if test -z "$mac" -o ${mac#\#} != $mac; then continue; fi
    #if test "$nm" = "$hostnm"; then continue; fi
	cat<<-EOF
    	<tr><td><input size=12 type=text id="nm_$cnt" name="nm_$cnt" value="$nm"></td>
		<td><input size=12 type=text id="ip_$cnt" name="ip_$cnt" value="$ip"></td>
		<td><input type=submit name="_$cnt" value="Get" onclick="return getMAC('mac_$cnt','ip_$cnt', 'nm_$cnt')"></td>
		<td><input size=18 type=text id="mac_$cnt" name="mac_$cnt" value="$mac"></td></tr>
	EOF
    cnt=$((cnt+1))
done < $CONF_H

IFS=$oifs
for i in $(seq $cnt $((cnt+2))); do
	cat<<-EOF
		<tr><td><input size=12 type=text id="nm_$i" name="nm_$i"></td>
		<td><input size=12 type=text id="ip_$i" name="ip_$i"></td>
		<td><input type=submit name="_$i" value="Get" onclick="return getMAC('mac_$i','ip_$i','nm_$i')"></td>
		<td><input size=17 type=text id="mac_$i" name="mac_$i"></td></tr>
	EOF
done

cat<<-EOF
	</table></fieldset>
	<input type=hidden name=cnt_din value="$i">
EOF

if test -z "$NTPD_SERVER" -o "$NTPD_SERVER" = "no"; then
	dislntp=disabled
fi

ntp_advert="$(grep '^option:ntp-server' $CONF_O | tr ',\t' ' ' | cut -f2 -d' ')"

if test -z "$ntp_advert"; then
	chknntp="checked"
elif test "$ntp_advert" = "0.0.0.0"; then
	chklntp="checked"
else
	chksntp="checked"
fi

cat<<-EOF
	<fieldset><legend>Time Servers</legend><table>
	<tr>
		<td><input type=radio $chknntp name=ntp value=no onchange="toogle_ntp('true')"></td>
		<td colspan=2>Don't advertise any server</td></tr>
	<tr>
		<td><input type=radio $chklntp $dislntp name=ntp value=local onchange="toogle_ntp('true')"></td>
		<td colspan=2>Advertise only local NTP server</td></tr>
	<tr>
		<td><input type=radio $chksntp name=ntp value=server onchange="toogle_ntp('false')"></td>
		<td>Advertise only configured NTP servers</td></tr>
	</table></fieldset>
EOF

eval $(awk -F= '/enable-tftp/{print "tftp=checked"} \
		/tftp-root/{printf "tftproot=%s", substr($0,index($0,$2))}' $CONF_F)
tftproot=$(httpd -e "$tftproot")
if test -z "$tftp"; then
	tftpdis=disabled
fi

cat<<-EOF
	<script type="text/javascript">
		function browse_dir_popup(input_id) {
		    start_dir = document.getElementById(input_id).value;
		    if (start_dir == "")
		    	start_dir="/mnt";
			window.open("browse_dir.cgi?id=" + input_id + "&browse=" + start_dir, "Browse", "scrollbars=yes, width=500, height=500");
			return false;
		}
	</script>
	<fieldset><legend>TFTP server</legend>
	<table>
	<tr><td>Enable TFTP</td><td><input type=checkbox $tftp value=tftp name=tftp onchange="toogle_tftp()"></td></tr>
	<tr><td>Root Folder</td>
		<td><input id=tftproot $tftpdis type=text size=20 name=tftproot value="$tftproot">
		<input type=button $tftpdis name=ftpbrowse onclick="browse_dir_popup('tftproot')" value=Browse>
		</td></tr>
	</table></fieldset>
EOF

eval $(awk '/log-queries/{print "dnslog=CHECKED"} \
		/log-dhcp/{print "dhcplog=CHECKED"}' $CONF_F)

for ip in $pidl; do
	f=$(echo $ip | tr '.' '_')
	arping -qfc 3 $ip &
	eval pid_$f=$!
done

echo "<script type=\"text/javascript\">"

for ip in $pidl; do
	f=$(echo $ip | tr '.' '_')
	wait $(eval echo \$pid_$f)
	test $? = 0 && st="Up" || st="Down"
	echo "document.getElementById(\"st_$ip\").innerHTML = \"$st\" ;"
done
echo "</script>"

cat<<EOF	
	<fieldset><legend>Logging</legend><table>
	<tr><td>Log DNS queries</td>
		<td><input type=checkbox $dnslog name=dnslog value=true></td></tr>
	<tr><td>Log DHCP queries</td>
		<td><input type=checkbox $dhcplog name=dhcplog value=true></td></tr>
	</table></fieldset>
	<p><input type=hidden name=cnt_dns value="$i">
	<input type=submit name=submit value=Submit>$(back_button)
	
	</form></body></html>
EOF
