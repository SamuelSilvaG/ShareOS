#!/bin/bash
#
# Tests Transmission per account: shareos-transmission (one daemon per
# account, with its rights), the proxy /_shareos/cgi/transmission of the apps
# web server, the remote access for Transmission programs (S52tremote,
# /transmission/rpc) and the rpcd objects shareos.apptorrent and
# shareos.tremote – with the built ARM userland (qemu-user) in a chroot and
# the system app transmission-daemon.
#
#   sudo tests/test-transmission.sh [output/dns320l] [transmission-daemon.sapp]
#
# Needs the system app (make sysapps-pack). Peers are not reached (no
# internet needed): torrents are added from a magnet link and stay without data.
#
[ -n "${SHAREOS_TEST_UTS:-}" ] || exec unshare --uts env SHAREOS_TEST_UTS=1 "$0" "$@"
set -u
OUT=${1:-output/dns320l}
TOP=$(cd "$(dirname "$0")/.." && pwd)
case "$OUT" in /*) ;; *) OUT="$TOP/$OUT" ;; esac
SAPP=${2:-$(ls -t "$TOP"/output/sysapps/sapp/transmission-daemon-*.sapp 2>/dev/null | head -1)}
SQFS="$OUT/images/rootfs.squashfs"
UNSQ="$OUT/host/bin/unsquashfs"
QEMU=$(command -v qemu-arm-static) || { echo "install qemu-user-static"; exit 1; }
[ -f "$SQFS" ] || { echo "no $SQFS"; exit 1; }
[ -f "$SAPP" ] || { echo "no transmission-daemon .sapp – make sysapps-pack"; exit 1; }
PORT=${SHAREOS_TEST_TR_PORT:-18091}

T=$(mktemp -d /tmp/shareos-tr-test.XXXX)
R=$T/root
cleanup() {
	chroot "$R" /bin/sh -c '/usr/sbin/shareos-transmission stop-all; /etc/init.d/S52tremote stop; /etc/init.d/S51apps stop; /etc/init.d/S13rpcd stop; /etc/init.d/S12ubus stop' >/dev/null 2>&1
	for m in $(grep " $R/" /proc/mounts | awk '{print $2}' | sort -r); do umount -l "$m" 2>/dev/null; done
	if grep -q " $R/" /proc/mounts; then echo "still mounted below $R – not removed" >&2; else rm -rf "$T"; fi
}
trap cleanup EXIT

if [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]; then
	[ -e /proc/sys/fs/binfmt_misc/register ] || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
	echo ":qemu-arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:$QEMU:F" \
		> /proc/sys/fs/binfmt_misc/register
fi

"$UNSQ" -q -d "$R" "$SQFS" >/dev/null
mount -t proc proc "$R/proc"
mount --bind /dev "$R/dev"
mount -t tmpfs tmpfs "$R/tmp"
mkdir -p "$R/var/run/ubus" "$R/var/log" "$R/mnt/daten"
mount -t tmpfs tmpfs "$R/mnt/daten"

run() { chroot "$R" /usr/bin/env SHAREOS_APPS_ALLOW_FILE=1 /bin/sh -c "$*" 2>&1; }
pass=0; failed=0
check() { if eval "$2"; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; failed=$((failed+1)); fi; }
js() { python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($1) else 1)"; }

run "uci set storage.daten=volume; uci set storage.daten.uuid=0; uci commit storage; uci set apps.store.port=$PORT; uci set apps.store.https_port=$((PORT+1)); uci set shareos.web.https=0; uci commit apps; uci commit shareos" >/dev/null
run "echo anna1234 | shareos-users add anna user --home=daten --web=1 --files=1; echo bernd123 | shareos-users add bernd user --home=daten --web=1 --files=1" >/dev/null

# --- before the system app ------------------------------------------------------------
o=$(run "shareos-transmission start anna")
check "not installed: start says so" "echo '$o' | js \"'not installed' in d['error']\""

cp "$SAPP" "$R/tmp/td.sapp"
# installed the way rpcd does it (umask 077): still usable for every account
o=$(run "umask 077; shareos-apps install-file /tmp/td.sapp")
check "system apps folder readable for every account" "[ \"\$(stat -c %a $R/opt/shareos) \$(stat -c %a $R/opt/shareos/sysapps) \$(stat -c %a $R/opt/shareos/bin)\" = '755 755 755' ]"
run "chmod 700 /opt/shareos" >/dev/null; run "shareos-apps fix-perms" >/dev/null
check "root-only folder of older versions is repaired at boot" "[ \"\$(stat -c %a $R/opt/shareos)\" = 755 ]"
check "system app transmission-daemon installs" "echo '$o' | js \"d.get('id')=='transmission-daemon'\""
check "starter in /opt/shareos/bin" "[ -x $R/opt/shareos/bin/transmission-daemon ]"

# a web app with "files" + "torrent", one with "files" only
mkapp() {   # id perms
	mkdir -p $T/$1/files
	echo '<!doctype html><title>ok</title>' > $T/$1/files/index.html
	echo '<svg xmlns="http://www.w3.org/2000/svg"/>' > $T/$1/files/icon.svg
	python3 -c "import json; json.dump({'id':'$1','name':'$1','version':'1.0.0','publisher':'T','type':'webapp','entry':'index.html','icon':'icon.svg','description':{'de':'x','en':'x'},'permissions':$2}, open('$T/$1/app.json','w'))"
	(cd $T/$1 && tar -czf $R/tmp/$1.sapp app.json -C files .)
	run "shareos-apps install-file /tmp/$1.sapp" >/dev/null
}
mkapp tclient '["files","torrent"]'
mkapp fileonly '["files"]'
mkdir -p $T/bad/files; echo x > $T/bad/files/index.html; echo '<svg/>' > $T/bad/files/icon.svg
python3 -c "import json; json.dump({'id':'bad','name':'b','version':'1.0.0','publisher':'T','type':'webapp','entry':'index.html','icon':'icon.svg','description':{'de':'x','en':'x'},'permissions':['torrent']}, open('$T/bad/app.json','w'))"
(cd $T/bad && tar -czf $R/tmp/bad.sapp app.json -C files .)
check "torrent without files is refused" "run 'shareos-apps install-file /tmp/bad.sapp' | grep -q 'torrent.*needs'"
run "uci set apps.tclient.users='*'; uci set apps.fileonly.users='*'; uci commit apps" >/dev/null 2>&1
run "uci show apps | grep -q users" >/dev/null || true

run '/etc/init.d/S12ubus start && /etc/init.d/S13rpcd start && /etc/init.d/S51apps start' >/dev/null
i=0; until curl -s -o /dev/null "http://127.0.0.1:$PORT/" || [ $i -ge 30 ]; do sleep 0.5; i=$((i + 1)); done

# grants like the admin interface hands out (account, app, expiry)
grant() { local t; t=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'); mkdir -p $R/tmp/shareos-appgrants; printf '%s\n%s\n%d\n' "$1" "$2" $(( $(date +%s) + 3600 )) > $R/tmp/shareos-appgrants/$t; echo $t; }
GA=$(grant anna tclient); GB=$(grant bernd tclient); GF=$(grant anna fileonly); GR=$(grant root tclient)
tr() { curl -s -m 120 -X POST -d "$2" "http://127.0.0.1:$PORT/_shareos/cgi/transmission?g=$1"; }
code() { curl -s -m 60 -o /dev/null -w '%{http_code}' -X POST -d "$2" "http://127.0.0.1:$PORT/_shareos/cgi/transmission?g=$1"; }

check "no grant: 403" "[ \$(code 0123456789abcdef0123456789abcdef '{\"method\":\"session-get\"}') = 403 ]"
check "app without torrent permission: 403" "[ \$(code $GF '{\"method\":\"session-get\"}') = 403 ]"
o=$(tr $GA '{"method":"session-get"}')
check "first call starts anna's daemon, session-get works" "echo '$o' | js \"d['result']=='success' and d['arguments']['download-dir']=='home/Downloads'\""
check "internal settings hidden (config dir, RPC socket, scripts)" "echo '$o' | js \"'config-dir' not in d['arguments'] and 'rpc-bind-address' not in d['arguments'] and not any(k.startswith('script-') and k.endswith('filename') for k in d['arguments'])\""
check "anna's daemon runs as anna" "[ \"\$(run 'stat -c %U /proc/\$(cat /tmp/shareos-transmission/anna/pid)')\" = anna ]"
check "state in anna's home, not in the flash" "[ -f $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json ] && [ \"\$(run 'stat -c %U /mnt/daten/home/anna/.config/transmission-daemon/settings.json')\" = anna ]"
check "defaults for a small CPU: µTP off, 60/30 peers, nice 10" "echo '$o' | js \"not d['arguments']['utp-enabled'] and d['arguments']['peer-limit-global']==60 and d['arguments']['peer-limit-per-torrent']==30\" && [ \"\$(run 'cut -d\" \" -f19 /proc/\$(cat /tmp/shareos-transmission/anna/pid)/stat')\" = 10 ]"
check "RPC only on a Unix socket (no TCP port 9091)" "[ -S $R/tmp/shareos-transmission/anna/rpc.sock ] && ! (exec 3<>/dev/tcp/127.0.0.1/9091) 2>/dev/null"

MAG='magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=ShareOS-Test'
o=$(tr $GA "{\"method\":\"torrent-add\",\"arguments\":{\"filename\":\"$MAG\",\"paused\":true}}")
check "anna adds a magnet link" "echo '$o' | js \"d['result']=='success' and d['arguments'].get('torrent-added',{}).get('name')=='ShareOS-Test'\""
SID=fedcba9876543210fedcba9876543210; mkdir -p $R/tmp/shareos-sessions; echo anna > $R/tmp/shareos-sessions/$SID
chips() { run "ubus call shareos.status chips '{\"ubus_rpc_session\":\"$SID\"}'"; }
check "header chip: daemon running, torrent paused – no chip" "chips | js \"not any(c['id']=='svc:torrent' for c in d['chips'])\""
tr $GA '{"method":"torrent-start","arguments":{"ids":[1]}}' >/dev/null; sleep 2
check "header chip: a torrent downloads – TORRENT ↓ 1" "chips | js \"[c['detail'] for c in d['chips'] if c['id']=='svc:torrent']==['↓ 1']\""
tr $GA '{"method":"torrent-stop","arguments":{"ids":[1]}}' >/dev/null; sleep 1
check "header chip: stopped again – gone" "chips | js \"not any(c['id']=='svc:torrent' for c in d['chips'])\""
o=$(tr $GA '{"method":"torrent-get","arguments":{"fields":["id","name","downloadDir"]}}')
check "anna sees it, folder as home/Downloads" "echo '$o' | js \"[(t['name'],t['downloadDir']) for t in d['arguments']['torrents']]==[('ShareOS-Test','home/Downloads')]\""
o=$(tr $GB '{"method":"torrent-get","arguments":{"fields":["id","name"]}}')
check "bernd has his own daemon and does not see anna's torrents" "echo '$o' | js \"d['arguments']['torrents']==[]\" && [ -f $R/tmp/shareos-transmission/bernd/pid ]"

run "mkdir -p /mnt/daten/home/anna/Filme; chown anna /mnt/daten/home/anna/Filme" >/dev/null
o=$(tr $GA '{"method":"torrent-set-location","arguments":{"ids":[1],"location":"home/Filme","move":false}}')
check "folder of her own as <root>/<path>" "echo '$o' | js \"d['result']=='success'\""
check "her own folder as absolute path too" "[ \$(code $GA '{\"method\":\"session-set\",\"arguments\":{\"download-dir\":\"/mnt/daten/home/anna/Filme\"}}') = 200 ]"
check "bernd's folder refused" "[ \$(code $GA '{\"method\":\"torrent-set-location\",\"arguments\":{\"ids\":[1],\"location\":\"/mnt/daten/home/bernd\"}}') = 403 ]"
check "system folders refused" "[ \$(code $GA '{\"method\":\"session-set\",\"arguments\":{\"download-dir\":\"/etc\"}}') = 403 ]"
check "../ out of her folder refused" "[ \$(code $GA '{\"method\":\"session-set\",\"arguments\":{\"download-dir\":\"home/../bernd\"}}') = 403 ]"
check "torrent-add from a local path refused" "[ \$(code $GA '{\"method\":\"torrent-add\",\"arguments\":{\"filename\":\"/etc/shadow\"}}') = 403 ]"
check "unknown methods refused" "[ \$(code $GA '{\"method\":\"blocklist-update\"}') = 403 ]"
tr $GA '{"method":"session-set","arguments":{"script-torrent-done-enabled":true,"script-torrent-done-filename":"/bin/sh","rpc-bind-address":"0.0.0.0","speed-limit-down":123,"speed-limit-down-enabled":true}}' >/dev/null
o=$(tr $GA '{"method":"session-get"}')
check "session-set: allowed keys pass (speed limit)" "echo '$o' | js \"d['arguments']['speed-limit-down']==123 and d['arguments']['speed-limit-down-enabled']\""
check "rpcd object not reachable for web sessions" "! grep -q apptorrent $R/usr/share/rpcd/acl.d/shareos.json"

# --- watch folder: kept by the box, the daemon adds new .torrent files by itself ----------
run "mkdir -p /mnt/daten/home/anna/Watch && chown anna /mnt/daten/home/anna/Watch" >/dev/null
o=$(tr $GA '{"method":"session-set","arguments":{"watch-dir-enabled":true,"watch-dir":"home/Watch"}}')
check "watch folder: set as home/Watch" "echo '$o' | js \"d['result']=='success'\" && tr $GA '{\"method\":\"session-get\"}' | js \"d['arguments']['watch-dir']=='home/Watch' and d['arguments']['watch-dir-enabled']\""
check "watch folder: kept by the box for the next start" "[ \"\$(cat $R/mnt/daten/home/anna/.config/transmission-daemon/.shareos-watch)\" = /mnt/daten/home/anna/Watch ]"
check "watch folder: outside her folders refused" "[ \$(code $GA '{\"method\":\"session-set\",\"arguments\":{\"watch-dir-enabled\":true,\"watch-dir\":\"/etc\"}}') = 403 ] && [ \$(code $GA '{\"method\":\"session-set\",\"arguments\":{\"watch-dir-enabled\":true}}') = 400 ]"
python3 -c "
import hashlib
def b(x):
    if isinstance(x,int): return b'i%de'%x
    if isinstance(x,str): x=x.encode()
    if isinstance(x,bytes): return b'%d:'%len(x)+x
    if isinstance(x,dict): return b'd'+b''.join(b(k)+b(v) for k,v in sorted(x.items()))+b'e'
open('$T/watch.torrent','wb').write(b({'announce':'http://127.0.0.1:1/announce','info':{'name':'Watch-Test','length':16384,'piece length':16384,'pieces':hashlib.sha1(b'\0'*16384).digest()}}))"
cp $T/watch.torrent $R/mnt/daten/home/anna/Watch/watch.torrent; run "chown anna /mnt/daten/home/anna/Watch/watch.torrent" >/dev/null
for i in $(seq 40); do tr $GA '{"method":"torrent-get","arguments":{"fields":["name"]}}' | js "'Watch-Test' in [t['name'] for t in d['arguments']['torrents']]" && break; sleep 1; done
check "a .torrent dropped into it is added by the daemon (app closed)" "tr $GA '{\"method\":\"torrent-get\",\"arguments\":{\"fields\":[\"name\"]}}' | js \"'Watch-Test' in [t['name'] for t in d['arguments']['torrents']]\""
WID=$(tr $GA '{"method":"torrent-get","arguments":{"fields":["id","name"]}}' | python3 -c "import json,sys; print([t['id'] for t in json.load(sys.stdin)['arguments']['torrents'] if t['name']=='Watch-Test'][0])")
tr $GA "{\"method\":\"torrent-remove\",\"arguments\":{\"ids\":[$WID]}}" >/dev/null
o=$(tr $GA '{"method":"session-set","arguments":{"watch-dir-enabled":false}}')
check "watch folder: switched off, also for the next start" "tr $GA '{\"method\":\"session-get\"}' | js \"not d['arguments']['watch-dir-enabled']\" && [ ! -e $R/mnt/daten/home/anna/.config/transmission-daemon/.shareos-watch ]"
tr $GA '{"method":"session-set","arguments":{"watch-dir-enabled":true,"watch-dir":"home/Watch"}}' >/dev/null

# --- peer port: kept by the box per account, checked ----------------------------------
o=$(tr $GA '{"method":"session-get"}')
check "peer port: anna's default (51413 + uid - 999), bernd another one" "echo '$o' | js \"d['arguments']['peer-port']==51413+$(run 'id -u anna')-999\" && tr $GB '{\"method\":\"session-get\"}' | js \"d['arguments']['peer-port']==51413+$(run 'id -u bernd')-999\""
o=$(tr $GA '{"method":"session-set","arguments":{"peer-port":52140}}')
check "peer port: set to 52140" "echo '$o' | js \"d['result']=='success'\" && tr $GA '{\"method\":\"session-get\"}' | js \"d['arguments']['peer-port']==52140\""
check "peer port: kept by the box for the next start" "[ \"\$(cat $R/mnt/daten/home/anna/.config/transmission-daemon/.shareos-peerport)\" = 52140 ] && grep -q '\"peer-port\": 52140' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json"
check "peer port: below 1024, above 65535, not a number refused" "[ \$(code $GA '{\"method\":\"session-set\",\"arguments\":{\"peer-port\":80}}') = 400 ] && [ \$(code $GA '{\"method\":\"session-set\",\"arguments\":{\"peer-port\":70000}}') = 400 ] && [ \$(code $GA '{\"method\":\"session-set\",\"arguments\":{\"peer-port\":\"x\"}}') = 400 ]"
check "peer port: bernd cannot take anna's port or her default" "tr $GB '{\"method\":\"session-set\",\"arguments\":{\"peer-port\":52140}}' | grep -q 'another account' && tr $GB '{\"method\":\"session-set\",\"arguments\":{\"peer-port\":'\$((51413+$(run 'id -u anna')-999))'}}' | grep -q 'default of another account'"
check "peer port: services of the box and Syncthing refused" "tr $GB '{\"method\":\"session-set\",\"arguments\":{\"peer-port\":8200}}' | grep -q 'service of the box' && tr $GB '{\"method\":\"session-set\",\"arguments\":{\"peer-port\":22001}}' | grep -q Syncthing"
check "peer port: a port in use refused (the apps web server)" "tr $GB '{\"method\":\"session-set\",\"arguments\":{\"peer-port\":$PORT}}' | grep -q 'in use'"
check "peer port: random port does not pass" "tr $GA '{\"method\":\"session-set\",\"arguments\":{\"peer-port-random-on-start\":true}}' >/dev/null; ! grep -q '\"peer-port-random-on-start\": true' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json"
# a value written into her folder (over SMB) is checked again at the start
echo 8200 > $R/mnt/daten/home/anna/.config/transmission-daemon/.shareos-peerport
run "shareos-transmission stop anna; shareos-transmission start anna" >/dev/null
check "peer port: a bad value in her folder falls back to the default" "grep -q '\"peer-port\": '\$((51413+$(run 'id -u anna')-999)) $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json"
run "shareos-transmission port anna 52140" >/dev/null

o=$(tr $GR '{"method":"session-get"}')
check "admin: own daemon as root, downloads on the volume" "echo '$o' | js \"d['arguments']['download-dir']=='daten/Downloads'\" && [ \"\$(run 'stat -c %U /proc/\$(cat /tmp/shareos-transmission/root/pid)')\" = root ]"

tr $GA '{"method":"session-set","arguments":{"utp-enabled":true,"peer-limit-global":90}}' >/dev/null
run "shareos-transmission stop anna" >/dev/null
run "shareos-transmission start anna" >/dev/null; run "shareos-transmission stop anna" >/dev/null
check "watch folder still set after the restart" "grep -q '\"watch-dir\": \"/mnt/daten/home/anna/Watch\"' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json && grep -q '\"watch-dir-enabled\": true' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json"
check "peer port still set after the restart" "grep -q '\"peer-port\": 52140' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json"
check "the user's own settings stay after a restart (defaults only once)" "grep -q '\"utp-enabled\": true' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json && grep -q '\"peer-limit-global\": 90' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json"
check "scripts and RPC address never reached the daemon" "grep -q '\"script-torrent-done-enabled\": false' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json && ! grep -q '/bin/sh' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json && grep -q '\"rpc-bind-address\": \"unix:' $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json"
check "accounts remembered for the next start" "[ -f $R/etc/shareos/transmission/anna ] && [ -f $R/etc/shareos/transmission/bernd ]"
run "shareos-transmission stop-all" >/dev/null
check "stop-all ends the daemons" "! run \"pgrep -f '[/]bin/transmission-daemon '\" | grep -q ."
o=$(run "shareos-transmission boot")
check "boot starts them again, torrents kept" "echo '$o' | js \"sorted(d['started'])==['anna','bernd','root']\" && tr $GA '{\"method\":\"torrent-get\",\"arguments\":{\"fields\":[\"name\"]}}' | js \"[t['name'] for t in d['arguments']['torrents']]==['ShareOS-Test']\""
# --- remote access for Transmission programs (S52tremote, /transmission/rpc) ----------
TRP=$((PORT + 2))
rurl() { echo "http://127.0.0.1:$TRP/transmission/rpc"; }
rpc_() { curl -s -m 120 -u "$1" -X POST -d "$2" "$(rurl)"; }                                         # user:pass body
rcode() { curl -s -m 60 -o /dev/null -w '%{http_code}' -u "$1" -X POST -d "$2" "$(rurl)"; }
ub() { run "ubus call shareos.apptorrent $1 '$2'"; }
check "remote access: off by default, nothing listens" "! (exec 3<>/dev/tcp/127.0.0.1/$TRP) 2>/dev/null && ub remote_session '{\"user\":\"anna\",\"pass\":\"x\",\"ip\":\"127.0.0.1\"}' | js \"d['error']=='off'\""
o=$(run "ubus call shareos.tremote set '{\"enabled\":true,\"port\":$PORT,\"https_port\":$((TRP + 1))}'")
o2=$(run "ubus call shareos.tremote set '{\"enabled\":true,\"port\":80,\"https_port\":$((TRP + 1))}'")
check "remote access: ports of the box and below 1024 are refused" "echo '$o' | grep -q 'service of the box' && echo '$o2' | grep -q 'between 1024 and 65535'"
o=$(run "ubus call shareos.tremote set '{\"enabled\":true,\"port\":$TRP,\"https_port\":$TRP}'")
check "remote access: HTTP and HTTPS need two ports" "echo '$o' | grep -q 'two different ports'"
o=$(run "ubus call shareos.tremote set '{\"enabled\":true,\"port\":$TRP,\"https_port\":$((TRP + 1))}'")
i=0; until (exec 3<>/dev/tcp/127.0.0.1/$TRP) 2>/dev/null || [ $i -ge 30 ]; do sleep 0.5; i=$((i + 1)); done
check "remote access: switched on, own web server runs" "echo '$o' | js \"d['enabled'] and d['running'] and d['port']==$TRP and d['installed'] and d['accounts']==[]\" && [ \"\$(run 'uci -q get shareos.tremote.enabled')\" = 1 ]"
check "remote access: only /transmission/rpc (no web interface, no files)" "( for u in / /transmission/web/ /transmission/ /index.html; do c=\$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$TRP\$u); [ \$c != 200 ] || exit 1; done )"
o=$(tr $GA '{"method":"shareos-remote-get"}')
check "app: remote access of anna – no password yet, address shown" "echo '$o' | js \"d['result']=='success' and not d['arguments']['on'] and d['arguments']['box_enabled'] and d['arguments']['port']==$TRP and d['arguments']['path']=='/transmission/rpc' and d['arguments']['user']=='anna'\""
check "app without torrent permission: no remote access" "[ \$(code $GF '{\"method\":\"shareos-remote-get\"}') = 403 ]"
o=$(tr $GA '{"method":"shareos-remote-set","arguments":{"on":true}}')
PA=$(echo "$o" | python3 -c "import json,sys; print(json.load(sys.stdin)['arguments'].get('password',''))")
check "app: password made by the box (4×4 characters), shown once" "echo '$PA' | grep -qE '^[a-z2-9]{4}(-[a-z2-9]{4}){3}\$' && tr $GA '{\"method\":\"shareos-remote-get\"}' | js \"d['arguments']['on'] and 'password' not in d['arguments']\""
check "only its hash is kept, root only" "grep -q '^\\\$5\\\$' $R/etc/shareos/tremote/anna && ! grep -q '$PA' $R/etc/shareos/tremote/anna && [ \"\$(stat -c %a $R/etc/shareos/tremote/anna) \$(stat -c %a $R/etc/shareos/tremote)\" = '600 700' ]"
o=$(tr $GA '{"method":"shareos-remote-set","arguments":{"on":true}}')
check "app: switching on again keeps the password" "echo '$o' | js \"'password' not in d['arguments'] and d['arguments']['on']\""
check "no name and password: 401 asking for basic auth" "curl -s -D - -o /dev/null -X POST -d '{\"method\":\"session-get\"}' $(rurl) | grep -qi '^WWW-Authenticate: Basic'"
check "wrong password: 401" "[ \$(rcode anna:wrong-pass '{\"method\":\"session-get\"}') = 401 ]"
check "the box password does not open it" "[ \$(rcode anna:anna1234 '{\"method\":\"session-get\"}') = 401 ]"
o=$(rpc_ "anna:$PA" '{"method":"session-get","tag":7}')
check "right password: session-get of anna's daemon, folders as /<root>/<path>" "echo '$o' | js \"d['result']=='success' and d['tag']==7 and d['arguments']['download-dir'].startswith('/home/') and 'rpc-bind-address' not in d['arguments']\""
o=$(rpc_ "anna:$PA" '{"method":"torrent-get","arguments":{"fields":["name","downloadDir"]}}')
check "remote: anna's torrents" "echo '$o' | js \"'ShareOS-Test' in [t['name'] for t in d['arguments']['torrents']] and all(t['downloadDir'].startswith('/home/') for t in d['arguments']['torrents'])\""
o=$(rpc_ "anna:$PA" '{"method":"torrent-set-location","arguments":{"ids":[1],"location":"/home/Filme","move":false}}')
check "remote: her folder as /home/Filme" "echo '$o' | js \"d['result']=='success'\" && rpc_ anna:$PA '{\"method\":\"torrent-get\",\"arguments\":{\"ids\":[1],\"fields\":[\"downloadDir\"]}}' | js \"d['arguments']['torrents'][0]['downloadDir']=='/home/Filme'\""
o=$(rpc_ "anna:$PA" '{"method":"torrent-set-location","arguments":{"ids":[1],"location":"/mnt/daten/home/bernd"},"tag":3}')
check "remote: bernd's folder refused (as a result the program shows)" "echo '$o' | js \"d['result'].startswith('folder not allowed') and d['tag']==3\""
check "remote: unknown methods refused" "rpc_ anna:$PA '{\"method\":\"blocklist-update\"}' | js \"d['result']=='method not allowed'\""
check "remote: watch folder and peer port with the ticket of the request" "rpc_ anna:$PA '{\"method\":\"session-set\",\"arguments\":{\"peer-port\":52141}}' | js \"d['result']=='success'\" && rpc_ anna:$PA '{\"method\":\"session-get\"}' | js \"d['arguments']['peer-port']==52141 and d['arguments']['watch-dir']=='/home/Watch'\""
check "a made-up ticket opens nothing" "ub path '{\"ticket\":\"0123456789abcdef0123456789abcdef\",\"root\":\"home\",\"path\":\"\"}' | js \"d['error']=='no access'\""
check "a browser (Origin) is refused" "[ \$(curl -s -o /dev/null -w '%{http_code}' -u anna:$PA -H 'Origin: http://evil.example' -X POST -d '{\"method\":\"session-get\"}' $(rurl)) = 403 ]"
check "anna's password does not open bernd's account" "[ \$(rcode bernd:$PA '{\"method\":\"session-get\"}') = 401 ]"
PB=$(tr $GB '{"method":"shareos-remote-set","arguments":{"on":true}}' | python3 -c "import json,sys; print(json.load(sys.stdin)['arguments'].get('password',''))")
check "bernd with his own password sees only his torrents" "rpc_ bernd:$PB '{\"method\":\"torrent-get\",\"arguments\":{\"fields\":[\"name\"]}}' | js \"d['arguments']['torrents']==[]\""
check "admin page lists the accounts with a password" "run 'ubus call shareos.tremote get' | js \"d['accounts']==['anna','bernd']\""
check "home network: private IPv4, Tailscale/CGNAT, IPv4 in IPv6, ULA, link-local" "( for ip in 10.1.2.3 172.20.0.9 192.168.178.20 100.101.102.103 ::ffff:192.168.0.7 fd7a:115c:a1e0::1 fe80::1 169.254.3.4; do ub remote_session '{\"user\":\"anna\",\"pass\":\"$PA\",\"ip\":\"'\$ip'\"}' | js \"d.get('user')=='anna'\" || exit 1; done )"
check "internet addresses refused" "( for ip in 8.8.8.8 172.32.0.1 192.169.1.1 100.128.0.1 2001:db8::1 ::ffff:8.8.8.8 ''; do ub remote_session '{\"user\":\"anna\",\"pass\":\"$PA\",\"ip\":\"'\$ip'\"}' | js \"d['error']=='not local'\" || exit 1; done )"
for i in 1 2 3 4 5; do ub remote_session '{"user":"bernd","pass":"nope","ip":"10.9.9.9"}' >/dev/null; done
check "5 wrong passwords lock the account name (also with the right one)" "ub remote_session '{\"user\":\"bernd\",\"pass\":\"$PB\",\"ip\":\"10.9.9.8\"}' | js \"d['error']=='locked'\""
check "… and the address (also for other accounts)" "ub remote_session '{\"user\":\"anna\",\"pass\":\"$PA\",\"ip\":\"10.9.9.9\"}' | js \"d['error']=='locked'\""
check "… and say so over HTTP (429)" "for i in 1 2 3 4 5; do rcode bernd:nope '{\"method\":\"session-get\"}' >/dev/null; done; [ \$(rcode bernd:$PB '{\"method\":\"session-get\"}') = 429 ]"
check "other accounts from other addresses still get in" "[ \$(rcode anna:$PA '{\"method\":\"session-get\"}') = 200 ]"
rm -f $R/tmp/shareos-tremote/fail-*
OLD=$PA
PA=$(tr $GA '{"method":"shareos-remote-set","arguments":{"on":true,"regen":true}}' | python3 -c "import json,sys; print(json.load(sys.stdin)['arguments'].get('password',''))")
check "new password: the old one stops working at once" "[ '$PA' != '$OLD' ] && [ \$(rcode anna:$OLD '{\"method\":\"session-get\"}') = 401 ] && [ \$(rcode anna:$PA '{\"method\":\"session-get\"}') = 200 ]"
rm -f $R/tmp/shareos-tremote/fail-*
run "uci delete apps.app_tclient.users; uci add_list apps.app_tclient.users=bernd; uci commit apps" >/dev/null
check "anna loses the Transmission app: remote access ends too" "[ \$(rcode anna:$PA '{\"method\":\"session-get\"}') = 401 ]"
run "uci delete apps.app_tclient.users; uci add_list apps.app_tclient.users='*'; uci commit apps" >/dev/null; rm -f $R/tmp/shareos-tremote/fail-*
check "… and is back with the app" "[ \$(rcode anna:$PA '{\"method\":\"session-get\"}') = 200 ]"
o=$(run "ubus call shareos.tremote revoke '{\"user\":\"bernd\"}'")
check "admin revokes bernd's password" "echo '$o' | js \"d['accounts']==['anna']\" && [ \$(rcode bernd:$PB '{\"method\":\"session-get\"}') = 401 ]"
rm -f $R/tmp/shareos-tremote/fail-*
tr $GA '{"method":"shareos-remote-set","arguments":{"on":false}}' >/dev/null
check "app: switched off, the password is gone" "[ ! -e $R/etc/shareos/tremote/anna ] && [ \$(rcode anna:$PA '{\"method\":\"session-get\"}') = 401 ]"
rm -f $R/tmp/shareos-tremote/fail-*
PA=$(tr $GA '{"method":"shareos-remote-set","arguments":{"on":true}}' | python3 -c "import json,sys; print(json.load(sys.stdin)['arguments'].get('password',''))")
run "uci set shareos.web.https=1; uci commit shareos; shareos-cert ensure; /etc/init.d/S52tremote restart" >/dev/null 2>&1
i=0; until (exec 3<>/dev/tcp/127.0.0.1/$((TRP + 1))) 2>/dev/null || [ $i -ge 40 ]; do sleep 0.5; i=$((i + 1)); done
check "HTTPS on the second port, with the box's certificate" "curl -sk -m 60 -u anna:$PA -X POST -d '{\"method\":\"session-get\"}' https://127.0.0.1:$((TRP + 1))/transmission/rpc | js \"d['result']=='success'\""
run "uci set shareos.web.https=0; uci commit shareos" >/dev/null
o=$(run "ubus call shareos.tremote set '{\"enabled\":false}'")
check "switched off: web server gone, logins refused" "echo '$o' | js \"not d['enabled'] and not d['running']\" && ! (exec 3<>/dev/tcp/127.0.0.1/$TRP) 2>/dev/null && ub remote_session '{\"user\":\"anna\",\"pass\":\"$PA\",\"ip\":\"127.0.0.1\"}' | js \"d['error']=='off'\""
run "shareos-users del bernd" >/dev/null 2>&1
check "deleting an account removes its remote password" "[ ! -e $R/etc/shareos/tremote/bernd ]"

run "shareos-apps remove transmission-daemon" >/dev/null
check "removing the system app stops the daemons" "! run \"pgrep -f '[/]bin/transmission-daemon '\" | grep -q . && [ ! -e $R/opt/shareos/bin/transmission-daemon ]"
check "downloads and state stay on the drive" "[ -f $R/mnt/daten/home/anna/.config/transmission-daemon/settings.json ]"

echo
echo "$pass passed, $failed failed"
[ $failed -eq 0 ]
