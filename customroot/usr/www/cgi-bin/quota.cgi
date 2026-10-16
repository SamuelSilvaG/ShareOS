#!/bin/sh

. common.sh
check_cookie

write_header "Quota Setup"
has_disks
parse_qstring
#debug

CONFP=/etc/passwd
CONFMISC=/etc/misc.conf

. $CONFMISC

quota_mopts='(usrquota|usrjquota|grpquota|grpjquota)'

cat<<-EOF
	<form name=frm action="/cgi-bin/quota_proc.cgi" method="post">
	<script type="text/javascript">
		function dis_toogle(obj, id) {
			tg = top.content.document.getElementById(id)
			if (obj.checked == true)
				tg.disabled = false
			else
				tg.disabled = true
		}
		function jsgoto(fs) {
			url="/cgi-bin/quota.cgi" + "?repfs=" + fs;
			window.location.assign(url)
		}
	</script>
EOF

if test -z "$user" -a -z "$group"; then

	echo "<table><tr><th>Dev.</th><th>Label</th><th class="highcol">Enabled</th><th class="highcol">Active</th></tr>"
	fs=$(grep -E '(ext2|ext3|ext4)' /proc/mounts | cut -d" " -f1)

	j=0
	for i in $fs; do
		j=$((j+1))
		part=$(basename $i)
		qm_chk="checked"; qm_dis=""
		if ! grep -Eq "^$i.*$quota_mopts" /proc/mounts; then
			qm_chk=""; qm_dis="disabled"
		else
			qs_chk="checked"
			if quotaon -p $i >& /dev/null; then
				qs_chk=""
			fi
		fi
		if test "$qm_chk" = "checked" -a "$qs_chk" = "checked"; then
			if test -z "$repfs"; then repfs=$part; fi
		fi
		cat<<-EOF
			<tr><td>$part</td><td>$(plabel $part)</td>
			<td class="highcol" align="center"><input $qm_chk type=checkbox name=enable_$j value="$part" onchange="dis_toogle(this, 'chk_$j')"><input $qm_chk type=hidden name=henable_$j value="$part"></td>
			<td class="highcol" align="center"><input $qm_dis $qs_chk type=checkbox id="chk_$j" name=active_$j value="$part"></td>
			<td><input $qm_dis type=submit name=$part value=checkNow onclick="return confirm('This operation takes a long time to accomplish the first\n\
time it is run, as it has to scan all files on the filesystem.\n\n\
It has to be done the first time quotas are enabled,\n\
and periodically afterwards, to ensure consistency.\n\n\
Continue?')"></td>
			<td><input $qm_dis type=button name=user value="Report" onclick="jsgoto('$part')"></td>
			</tr>
		EOF
	done
	
	if test "$QUOTAMAIL" = "y"; then
		mail_chk="checked"
	fi
	cat<<-EOF
		<tr><td colspan=2></td><td class="highcol" align="center" colspan=2></td></tr>
		</table><br>
		<input type=checkbox $mail_chk name=quotamail value="y"> Send e-mail to "$MAILTO" on disk over quotas<br>   (Use "Setup Mail" to change)<br>
		<input type=submit name=quota_global value="Submit">
		<input type=hidden name=glb_cnt value="$j">
	EOF
	
	if test -n "$repfs"; then
	
		sbd="style=\"border-right:1px solid #000\""
		cat<<-EOF
		<hr><table><tr><th></th><th colspan=8>Report for device $repfs</th></tr>
		<tr><th></th><th colspan=4 class="highcol" $sbd>Space Limits</th> <th colspan=4 class="highcol">File Limits</th></tr>
		
		<tr><th></th> <th class="highcol">Used</th> <th class="highcol">Warning</th> <th class="highcol">Max</th> <th class="highcol" $sbd>Grace</th> <th class="highcol">Used</th> <th class="highcol">Warning</th> <th class="highcol">Max</th> <th class="highcol">Grace</th> </tr>
		EOF
		
		if ! lbl=$(plabel /dev/$repfs); then lbl=$repfs; fi
		
		repquota -ugs -O csv /mnt/$lbl | awk -F, -v sbd="$sbd" '
			{
			if ($1 == "User" || $1 == "Group") {
				print "<tr><td></td></tr><tr><td colspan=9><strong><u>"$1" report</u></strong></td></tr>"
				if ($1 == "User") type="user"
				if ($1 == "Group") type="group"
				next
			}
			sp_col=""; lm_col=""
			if ($2 == "soft") sp_col="style=\"color:blue\"";
			if ($2 == "hard") sp_col="style=\"color:red\""; 
			if ($3 == "soft") lm_col="style=\"color:blue\"";
			if ($3 == "hard") lm_col="style=\"color:red\"";

			print "<tr>\
			<td><strong><a href=/cgi-bin/quota.cgi?"type"="$1"&repfs='$repfs'>"$1"</a></strong></td>\
			<td class=\"highcol\" "sp_col">"$4"</td>\
			<td class=\"highcol\" "sp_col">"$5"</td>\
			<td class=\"highcol\" "sp_col">"$6"</td>\
			<td class=\"highcol\" "sp_col" "sbd">"$7"</td>\
			<td class=\"highcol\" "lm_col">"$8"</td>\
			<td class=\"highcol\" "lm_col">"$9"</td>\
			<td class=\"highcol\" "lm_col">"$10"</td>\
			<td class=\"highcol\" "lm_col">"$11"</td>\
			</tr>"
		}'
		
		echo "</table>"
	fi

elif test -n "$user" -o -n "$group"; then
	
	if test -n "$user"; then
		type="user"; opt="-u"
		targ="$user"; name="$(awk -F: '/^'$user':/{printf "%s", $5}' $CONFP)"
	else
		type="group"; opt="-g"
		targ="$group"; name="$group"
	fi

	sbd="style=\"border-right:1px solid #000\""
	res=$(quota --show-mntpoint -pwvs $opt $targ 2> /dev/null)
	if test -n "$res"; then
		cat<<-EOF
			<h3>Set quota for $type "$name"</h3>
			<table>
			<tr> <th colspan=2></th> <th class="highcol" $sbd colspan=3>Space Limits</th>
			<th  class="highcol" colspan=3>File Limits</th></tr>
			<tr> <th>Dev.</th> <th>Label</th> <th class="highcol">Used</th>
			<th class="highcol">Warning</th> <th class="highcol" $sbd>Max</th>
			<th class="highcol">Used</td> <th class="highcol">Warn</th>
			<th class="highcol">Max</th></tr>
		EOF

		i=0
		echo "$res" | tail +3 | while read fs lbl blocks bquota blimit bgrace files fquota flimit fgrace; do
			i=$((i+1))
			fs=$(basename $fs)
			lbl=$(basename $lbl)
			if test "$lbl" = "$fs"; then lbl=""; fi
			berr=""; if echo "$blocks" | grep -q '*'; then
				berr="class=\"red\""
				blocks=$(echo $blocks | tr -d '*');
			fi
			ferr=""; if echo "$files" | grep -q '*'; then
				ferr="class=\"red\""
				files=$(echo $files | tr -d '*');
			fi
			cat<<-EOF
				<tr><td><input type=hidden name=fs_$i value="$fs">$fs</td>
					<td>$lbl</td>
					<td  $berr class=highcol>$blocks</td>
					<td class=highcol><input type=text size=6 name=bquota_$i value="$bquota"></td>
					<td class=highcol $sbd><input type=text size=6 name=blimit_$i value="$blimit"></td>
					<td $ferr class=highcol>$files</td>
					<td class=highcol><input type=text size=6 name=fquota_$i value="$fquota"></td>
					<td class=highcol><input type=text size=6 name=flimit_$i value="$flimit"></td></tr>
			EOF
		done
		cat<<-EOF
			</table><br>
			<input type=hidden name=repfs value="$repfs">
			<input type=submit name=quota_ug value="Submit">$(back_button)
		EOF
	else
		echo "<p>You have to setup Disk Quotas first.</p>$(back_button)"
	fi
fi

cat<<-EOF
	<input type=hidden name=targ value="$targ">
	<input type=hidden name=opt value="$opt">
	</form></body></html>
EOF
