#!/bin/sh
 
SERRORL=/var/log/systemerror.log

echo "<li>SMART: $SMARTD_MESSAGE</li>" >> $SERRORL
