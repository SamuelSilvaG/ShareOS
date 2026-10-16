#!/bin/sh
. common.sh

check_cookie
write_header "ShareOS Package Manager"

#debug

has_disks

CONFF=/etc/ipkg.conf

PREINST=/etc/preinst
PREINSTSQ=/etc/preinst-sq # not used

UBIROOT=/rootmnt/ubiimage
SQINST=$UBIROOT/usr/lib/ipkg/status

# read-only -- preinst?
ROROOT=/rootmnt/rw
ROINST=$ROROOT/usr/lib/ipkg/status # not in use

RWROOT=/rootmnt/rw
RWINST=$RWROOT/usr/lib/ipkg/status # not in use

mktt tt_rm_force "Force remove package, even if needed by other packages.<br> It must be re-installed as the dependent packages might stop working."
mktt tt_rm_deps "Also remove packages that depends on this package."
mktt tt_rm_orph "Also remove most packages (not all) that where installed as needed for this package and are not needed anymore."

cat<<-EOF
	<script type="text/javascript">
		function chkpriority(name, priority) {
			if (priority == "required" || priority == "important")
				if (confirm("Package \"" + name + "\" has a priority of \"" + priority + "\".\n Are you sure you want to remove it?\n\n"))
					return true
				else
					return false
			else
				return true
		}
	</script>

	<form name="form" action="/cgi-bin/packages_ipkg_proc.cgi" method="post">
	<fieldset><legend>Package Feeds</legend><table>
	<tr><th>Disabled</th><th>Label</th><th>Feed</th></tr>
EOF

cnt=1
while read type label feed; do
	cmt=""
	if test \( "$type" = "src" -o "$type" = "#!#src" \) -a -n "$feed"; then
		if test "$type" = "#!#src"; then
			cmt=checked
		fi
		cat<<-EOF
			<tr><td align="center"><input type=checkbox $cmt name=dis_$cnt></td>
			<td><input type=text size=12 name=lbl_$cnt value="$label"></td>
			<td><input type=text size=40 name=feed_$cnt value="$feed"></td></tr>
		EOF
		cnt=$((cnt+1))
	fi
done < $CONFF

cat<<-EOF
	<tr><td align="center"><input type=checkbox name=dis_$cnt></td>
	<td><input type=text size=12 name=lbl_$cnt value=""></td>
	<td><input type=text size=40 name=feed_$cnt value=""></td></tr>
	<tr><td></td><td colspan=2><input type=submit name=changeFeeds value=Submit>
	<input type=submit name=updatelist $updpkg_dis value=UpdatePackageList></td></tr>
	</table>
	<input type=hidden name=nfeeds value="$cnt">
	</fieldset>
	<fieldset><legend>Install Packages into</legend>
EOF

if mount -t ubifs | grep -qw $UBIROOT; then
	eval $(df -h $UBIROOT | awk '/ubiimage/{printf "tot=%s;used=%s;perc=%d", $2, $3, $5}')
	if test "$perc" -gt 90; then
		flashdis="disabled"
	fi
	flashln="<tr><td>flash memory:</td><td><input type=radio $flashdis $flashchk name="instdest" value="flash"></td><td colspan=2>$(drawbargraph $perc ${used}B/${tot}B)</td>
	<td><input type=submit name=ClearFlash value=\"ClearFlash\" onclick=\"return confirm('This action will uninstall all non-essential packages currently installed on flash.\n\nProceed?')\"></td>
	<td><input type=submit name=RestoreFlash value=\"RestoreFlash\" onclick=\"return confirm('This action will download and reinstall the default set of packages on flash.\n\nProceed?')\"></td>
	<td><input type=submit name=MoveFromDisk value=\"MoveFromDisk\" onclick=\"return confirm('This action will move, if possible, packages installed on disk to flash.\n\nProceed?')\"></td></tr>"
else
	noubi=1
	diskln_e=", changes will be made to volatile RAM memory"
fi

install_loc=$(find /mnt -type d -maxdepth 2 -user root -name ShareOS 2>/dev/null)
if test -z "$install_loc" || ! aufs.sh -s >& /dev/null; then
	suggest=$(basename $(dirname $(realpath /ShareOS))) >& /dev/null
	diskln="<td><span class=warn>No ShareOS on disk package installation folder found</td></tr>
	<tr><td colspan=2></td><td>Install in: $(select_part $suggest) <input type=submit name=install value=Install></td></tr>"
else
	diskln="<th>FS</th><th class="highcol">Boot Enabled</th><th>Status</th>"
	if ! aufs.sh -s >& /dev/null; then diskdis=disabled; fi
fi

diskchk=checked

cat<<-EOF
<table>
$flashln
<tr><td>disk drive:</td><td><input type=radio $diskdis $diskchk name="instdest" value="root"></td>$diskln</tr>
EOF

if test -z "$install_loc" -a "$noubi" = 1; then
	echo "</table></fieldset>"
	echo "</form></body></html>"
	exit 0
fi

 if test -n "$install_loc"; then
	active=$(aufs.sh -l | grep /mnt/ | cut -f1 -d=)
	j=0
	for i in $install_loc; do
		j=$((++j))
		
		bootchk=""
		if ! test -f "$i"/NOAUFS; then
			bootchk=checked
		fi
		
		act="ActivateNow"; st="Inactive"
		#if test "$(realpath /ShareOS 2> /dev/null)" = "$i"; then
		if test "$i" = "$active"; then
			act="DeactivateNow"; st="<strong>Active</strong>"
		fi

		cat<<-EOF
			<tr><td colspan=2></td><td>$(basename $(dirname $i))</td>
			<td class="highcol" align="center"><input type=checkbox $bootchk name="$i" value="BootEnable_$j"></td>
			<td>$st</td>
			<td><input style="width:100%" type=submit name="$i" value=$act></td>
			<td><input type=submit name="$i" value=Delete onClick="return confirm('Delete $i and all its files and subfolders?\nAll packages files and configurations will be deleted.\nYou will have to reinstall all ShareOS packages.')"></td>
			<td><input type=hidden name=altf_dir_$j value="$i">
			<input type=submit name="$j" value=CopyTo>$(select_part "" $j)</td>
			</tr>
		EOF
	done
	cat<<-EOF
		<tr><td colspan=3></td><td class="highcol"><input type=submit name="BootEnable" value="Submit"></td></tr>
		
		<input type=hidden name=ninstall value="$j"">
	EOF
fi

#if ipkg status >/dev/null; then
if test -x /usr/bin/ipkg-cl; then
	cat<<-EOF
		</table></fieldset>
		<fieldset><legend> Installed/Pre-installed Packages </legend>
		<table><tr><th>Remove options:</th></tr>
			<tr><td>Force remove</td><td><input type=checkbox name=force_remove value=yes $(ttip tt_rm_force)></td></tr>
			<tr><td>Force remove all dependents</td><td><input type=checkbox name=rec_remove value=yes $(ttip tt_rm_deps)></td></tr>
			<tr><td>Remove most orphaned</td><td><input type=checkbox checked name=orphan_remove value=yes $(ttip tt_rm_orph)></td></tr>
			</table><br>
			<table><tr>
				<th>Name</th><th>Version</th><th>Where</th><th></th><th></th><th></th><th>Description</th></tr>
	EOF

	ipkg-cl -V0 info | awk -v preinst=$PREINST -v sqinst=$SQINST '
	BEGIN {
		if (system("test -f " preinst) == 0)
			while (getline ln < preinst) {
				split(ln,a);
				preinst[a[1]] = a[2];
			}
		if (system("test -f " sqinst) == 0)
			while (getline ln < sqinst) {
				split(ln,a);
				flash[a[1]] = a[2];
			}
	}
	/Package:/ { i++; nm=$2; pkg[i] = nm } # this relies on Package being the first field 
	/Version:/ { ver[i] = $2 }
	/Source:/ { url[i] = $2 }
	/Description:/ { des[i] = substr($0, index($0,$2)) }
	/Priority:/ { pri[i] = $2 }
	/Status:/ {
		if ($4 == "installed") # && $2 != "deinstall")
			inst[nm] = i
		else if ($4 == "not-installed") {
			uinst[nm] = i
			ucnt++
			}
		}
	END {
		update = 0;
		for (i=1; pkg[i] != ""; i++) {
			nm = pkg[i]
			
			if (nm in inst || nm in preinst) {

				remdis = ""
				if (nm in preinst) { # fw preinstalled
					if (preinst[nm] == ver[inst[nm]]) { # fw original, same version
						remdis = "disabled"
						dest="-"
					} else if (nm in flash) # updated on flash
						dest="F"
					else  # updated on disk
						dest="D"
				} else {
					if (nm in flash)
						dest="F"
					else
						dest="D"
				}
				
				rmv = sprintf("<td><input type=submit %s name=%s value=Remove onclick=\"return chkpriority(%c%s%c, %c%s%c)\"></td>", remdis, nm, 0x27, nm, 0x27, 0x27, pri[i], 0x27);

				if (nm in uinst) {	# new version available, old might have missing info
					j = uinst[nm]; update++;

					if (nm in preinst && ! (nm in inst))
						v = preinst[nm]
					else
						v = ver[inst[nm]];

					if (system("ipkg-cl -V0 compare_versions " v " \">\" " ver[uinst[nm]]))
						upd="<td></td><td></td>";
					else
						upd = sprintf("<td><input type=submit name=%s value=Update></td><td>(%s)</td>", nm, ver[uinst[nm]]);

					delete uinst[nm]; ucnt--; delete inst[nm]; delete preinst[nm]
				} else {
					j = i; v = ver[i];
					upd="<td></td><td></td>";
				}

				printf "<tr><td><a href=\"/cgi-bin/embed.cgi?name=%s&site=%s\">%s</a></td><td>%s</td><td>%s</td>",
					nm, url[j], nm, v, dest;
				print rmv;
				print upd;
				printf "<td>%s</td></tr>\n\n", des[j];
			}
		}
	
		print "<tr><td colspan=6><br></td></tr>"
		if (update != 0)
			print "<tr><td colspan=2><strong>Update all installed</strong></td> \
				<td></td><td><input type=submit name=updateall value=UpdateAll></td></tr>"

		print "</table></fieldset> \
			<fieldset><legend> Available Packages </legend><table>"

		if (ucnt == 0) {
			print "None"
		} else {
			print "<tr><th>Name</th><th>Version</th> \
				<th></th><th>Description</th></tr>"

			for (i=1; pkg[i] != ""; i++) {
				nm = pkg[i];
				if (nm in uinst) {
					delete uinst[nm] # remove multi-arch duplicates
					printf "<tr><td><a href=\"/cgi-bin/embed.cgi?name=%s?site=%s\">%s</a></td><td>%s</td>",
					nm, url[i], nm, ver[i];
					printf "<td><input type=submit name=%s value=Install></td>", nm;
					printf "<td>%s</td></tr>\n\n", des[i];
				}
			}
		printf "</table></fieldset>"
		}
	}'
fi

echo "</form></body></html>"

