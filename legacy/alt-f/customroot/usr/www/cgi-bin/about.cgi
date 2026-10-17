#!/bin/sh

. common.sh
write_header "About ShareOS"

cat<<-EOF

<p>ShareOS is a <a href="http://en.wikipedia.org/wiki/Free_software">free</a>
and open source alternative firmware for the D-Link DNS-320/320L/321/323/325/327L,
DNR-322L and compatible NAS, forked from <a href="http://sourceforge.net/projects/alt-f" target=_blank>Alt-F</a>.
<p>
<a href="https://github.com/UniqueDroid/ShareOS" target=_blank>Main site</a><br>
<a href="http://groups.google.com/group/alt-f" target=_blank>Alt-F Support Forum</a><br>
<a href="http://sourceforge.net/p/alt-f/wiki/Home" target=_blank>Alt-F Wiki</a><br>

<h3>Copyright</h3>	
<pre>$(cat /LICENSE)</pre>

<h3>License</h3>
<pre>$(cat /COPYING)</pre>

</body></html>
EOF

