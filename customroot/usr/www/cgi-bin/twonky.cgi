#!/bin/sh

. common.sh
check_cookie
read_args

if ! rctwonky status >& /dev/null; then
	rctwonky start >& /dev/null
fi

# the twonky server sends a "X-Frame-options: SAMEORIGIN" that impeachs embedding

html_header
cat<<EOF
<script type="text/javascript">
	function twonky_page() {
		if (location.protocol == "http:")
				port = ":9000";
		else if (location.protocol == "https:")
				port = ":9443";
		else
				return;
		window.parent.location.replace(location.protocol + "//" + location.hostname + port, "Twonky");
	}

	twonky_page()
</script><body></html>
EOF
