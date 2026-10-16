#!/bin/sh

SYSERRLOG=/var/log/systemerror.log
MISCCONF=/etc/misc.conf

. $MISCCONF

rep=$(repquota -uga | awk '
	function rep() {
		printf("<li>%s \"%s\" has exceeded his %s disk quota limits on device %s</li>\n",
		type, ug, warn, fs) 
	}
	/Report for/ { type=$4; fs=$8 }
	/\+\-/ { ug=$1; warn="space"; rep() }
	/\-\+/ { ug=$1; warn="file"; rep() }
	/\+\+/ { ug=$1; warn="file and space"; rep() }
	')

	if test -n "$rep"; then
		echo "$rep" >> $SYSERRLOG
		
		if test "$QUOTAMAIL" = "y" -a -n "$MAILTO"; then
			echo "$rep" | sed -n 's|<li>\(.*\)</li>|\1|p' | mail -s "Quota warning for host $(hostname -f) on $(date)" $MAILTO
		fi
	fi
