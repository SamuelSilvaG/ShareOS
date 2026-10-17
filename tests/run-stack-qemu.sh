#!/bin/bash
#
# Runs the built ShareOS userland (ARM) on the build host with qemu-user:
# ubusd + rpcd (with the ShareOS ucode plugin) + uhttpd, serving the web UI
# on http://127.0.0.1:<port>/ – for backend and GUI development without
# hardware. Board-specific parts (MCU, LEDs, flash) are not available.
#
#   sudo tests/run-stack-qemu.sh [output/dns320l] [port] [--check]
#
#   --check   run JSON-RPC smoke tests, then stop again
#
# Needs root (chroot, mounts), qemu-user-static and binfmt_misc.
#
set -euo pipefail
OUT=${1:-output/dns320l}
PORT=${2:-8080}
CHECK=${3:-}
TOP=$(cd "$(dirname "$0")/.." && pwd)
case "$OUT" in /*) ;; *) OUT="$TOP/$OUT" ;; esac
SQFS="$OUT/images/rootfs.squashfs"
UNSQ="$OUT/host/bin/unsquashfs"
[ -f "$SQFS" ] || { echo "no $SQFS – build first (make dns320l)"; exit 1; }
QEMU=$(command -v qemu-arm-static) || { echo "install qemu-user-static"; exit 1; }

R=$(mktemp -d /tmp/shareos-qemu.XXXX)
cleanup() {
	chroot "$R" /bin/sh -c '/etc/init.d/S50uhttpd stop; /etc/init.d/S13rpcd stop; /etc/init.d/S12ubus stop' >/dev/null 2>&1 || true
	umount "$R/dev" "$R/proc" 2>/dev/null || true
	rm -rf "$R"
}
trap cleanup EXIT

# binfmt for ARM ELF -> qemu (F = fix binary, works inside the chroot)
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]; then
	[ -e /proc/sys/fs/binfmt_misc/register ] || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
	echo ":qemu-arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:$QEMU:F" \
		> /proc/sys/fs/binfmt_misc/register
fi

rmdir "$R" && "$UNSQ" -q -d "$R" "$SQFS" >/dev/null
mkdir -p "$R/proc" "$R/dev"
mount -t proc proc "$R/proc"
mount --bind /dev "$R/dev"
sed -i "s/^PORT=.*/PORT=$PORT/; s/\${SHAREOS_HTTPS_PORT:-443}/$((PORT+363))/" "$R/usr/sbin/shareos-uhttpd"

chroot "$R" /bin/sh -c '/etc/init.d/S12ubus start && /etc/init.d/S13rpcd start && /etc/init.d/S50uhttpd start'
for i in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.2; done

rpc() { curl -s "http://127.0.0.1:$PORT/ubus" -H 'Content-Type: application/json' \
	-d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"$1\",\"$2\",\"$3\",${4:-{\}}]}"; }
ZERO=00000000000000000000000000000000

if [ "$CHECK" = "--check" ]; then
	fails=0
	t() { if printf '%s' "$2" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if ($3) else 1)"; then
		echo "PASS  $1"; else echo "FAIL  $1: $2"; fails=$((fails+1)); fi; }
	t "web root served" "$(curl -s -o /dev/null -w '{"c":%{http_code}}' http://127.0.0.1:$PORT/)" "d['c']==200"
	t "anonymous call denied" "$(rpc $ZERO shareos.system info)" "d['error']['code']==-32002"
	t "wrong password rejected" "$(rpc $ZERO session login '{"username":"root","password":"wrong"}')" "d['result'][0]==6"
	L=$(rpc $ZERO session login '{"username":"root","password":"shareos"}')
	t "login works, shareos-admin granted" "$L" "'shareos-admin' in d['result'][1]['acls']['access-group']"
	SID=$(printf '%s' "$L" | python3 -c "import json,sys;print(json.load(sys.stdin)['result'][1]['ubus_rpc_session'])")
	t "shareos.system info" "$(rpc $SID shareos.system info)" "d['result'][1]['release']['fwname']=='DNS-320L-rev-Ax'"
	t "uci get shareos" "$(rpc $SID uci get '{"config":"shareos"}')" "d['result'][1]['values']['update']['repo']=='UniqueDroid/ShareOS'"
	t "apply needs confirm" "$(rpc $SID shareos.update apply '{"tag":"v0"}')" "'confirm' in d['result'][1]['error']"
	t "update status" "$(rpc $SID shareos.update status)" "'state' in d['result'][1]"
	t "info: cpu, net counters, filesystems" "$(rpc $SID shareos.system info)" "d['result'][1]['cpu']['total']>0 and 'rx_bytes' in d['result'][1]['network']['eth0'] and 'filesystems' in d['result'][1]"
	t "service list" "$(rpc $SID shareos.service list)" "any(x['name']=='uhttpd' and x['running'] for x in d['result'][1]['services'])"
	t "essential service cannot be stopped" "$(rpc $SID shareos.service action '{"name":"rpcd","action":"stop"}')" "'cannot be stopped' in d['result'][1]['error']"
	t "unknown service rejected" "$(rpc $SID shareos.service action '{"name":"../../bin/sh","action":"start"}')" "d['result'][1]['error']=='unknown service'"
	t "log readable" "$(rpc $SID shareos.system log '{"lines":5,"source":"kernel"}')" "type(d['result'][1]['lines'])==list"
	t "factory reset needs confirm" "$(rpc $SID shareos.system factory_reset)" "'confirm' in d['result'][1]['error']"
	t "invalid hostname rejected" "$(rpc $SID shareos.system set_hostname '{"hostname":"bad name;x"}')" "d['result'][1]['error']=='invalid hostname'"
	t "short password rejected" "$(rpc $SID shareos.system set_password '{"password":"abc"}')" "'too short' in d['result'][1]['error']"
	t "anonymous service list denied" "$(rpc $ZERO shareos.service list)" "d['error']['code']==-32002"
	t "public: language/logo readable before login" "$(rpc $ZERO shareos.ui get)" "d['result'][1]['lang']=='en' and d['result'][1]['logo']==True"
	t "public: nothing else readable before login" "$(rpc $ZERO shareos.web get)" "d['error']['code']==-32002"
	t "self-signed certificate created on start" "$(rpc $SID shareos.web get)" "d['result'][1]['https'] and d['result'][1]['cert']['selfsigned'] and d['result'][1]['cert']['subject'].startswith('CN=')"
	t "HTTPS answers with that certificate" "$(curl -sk -o /dev/null -w '{"c":%{http_code}}' https://127.0.0.1:$((PORT+363))/)" "d['c']==200"
	t "own certificate: garbage rejected" "$(rpc $SID shareos.web install '{"cert":"x","key":"y"}')" "'PEM' in d['result'][1]['error']"
	t "language can be changed" "$(rpc $SID shareos.ui set '{"lang":"de"}')" "d['result'][1]['lang']=='de'"
	t "invalid language rejected" "$(rpc $SID shareos.ui set '{"lang":"../x"}')" "'invalid' in d['result'][1]['error']"
	t "hardware settings readable" "$(rpc $SID shareos.hw get)" "d['result'][1]['fan']['preset']=='balanced' and d['result'][1]['led']['status']=='heartbeat'"
	t "fan: custom curve validated" "$(rpc $SID shareos.hw set_fan '{"preset":"custom","off_temp":0,"full_temp":40,"half_temp":45}')" "'invalid' in d['result'][1]['error']"
	t "fan: custom curve stored" "$(rpc $SID shareos.hw set_fan '{"preset":"custom","off_temp":35,"full_temp":52,"half_temp":47}')" "d['result'][1]['fan']['full_temp']==52 and d['result'][1]['fan']['preset']=='custom'"
	t "LED setting stored" "$(rpc $SID shareos.hw set_led '{"power":"blink"}')" "d['result'][1]['led']['power']=='blink'"
	t "first run pending" "$(rpc $SID shareos.setup status)" "d['result'][1]['done']==False"
	t "time zones listed" "$(rpc $SID shareos.setup zones)" "'Europe/Berlin' in d['result'][1]['zones']"
	t "no Alt-F settings in the emulator" "$(rpc $SID shareos.setup altf)" "d['result'][1]['found']==False"
	t "first run: bad time zone rejected" "$(rpc $SID shareos.setup apply '{"timezone":"../../etc/passwd"}')" "'time zone' in d['result'][1]['error']"
	t "first run applied" "$(rpc $SID shareos.setup apply '{"timezone":"Europe/Vienna","channel":"beta"}')" "d['result'][1]['ok'] and 'timezone' in d['result'][1]['done']"
	t "first run done afterwards" "$(rpc $SID shareos.setup status)" "d['result'][1]['done']==True and d['result'][1]['timezone']=='Europe/Vienna'"
	t "look is system-wide (theme, accent)" "$(rpc $SID shareos.ui set '{"theme":"system","accent":"green"}')" "d['result'][1]['theme']=='system' and d['result'][1]['accent']=='green'"
	t "look readable before login" "$(rpc 00000000000000000000000000000000 shareos.ui get)" "d['result'][1]['accent']=='green'"
	t "invalid accent rejected" "$(rpc $SID shareos.ui set '{"accent":"pink"}')" "'invalid' in d['result'][1]['error']"
	t "services report autostart" "$(rpc $SID shareos.service list)" "all('autostart' in x for x in d['result'][1]['services'])"
	t "autostart can be switched off" "$(rpc $SID shareos.service autostart '{"name":"crond","enabled":false}')" "d['result'][1]['autostart']==False"
	t "autostart stored in UCI" "$(chroot "$R" uci -q get shareos.autostart.disabled | python3 -c 'import json,sys; print(json.dumps({"v":sys.stdin.read().split()}))')" "d['v']==['crond']"
	t "essential service always starts" "$(rpc $SID shareos.service autostart '{"name":"rpcd","enabled":false}')" "'always' in d['result'][1]['error']"
	t "autostart back on" "$(rpc $SID shareos.service autostart '{"name":"crond","enabled":true}')" "d['result'][1]['autostart']==True"
	t "network settings readable" "$(rpc $SID shareos.net get)" "d['result'][1]['proto']=='dhcp' and d['result'][1]['pending'] is None and d['result'][1]['timeout']==120"
	t "network change needs confirm" "$(rpc $SID shareos.net set '{"proto":"static","ipaddr":"10.0.0.5","netmask":"255.255.255.0"}')" "'confirm' in d['result'][1]['error']"
	t "network: bad mask rejected" "$(rpc $SID shareos.net set '{"proto":"static","ipaddr":"10.0.0.5","netmask":"255.0.255.0","confirm":true}')" "'mask' in d['result'][1]['error']"
	t "network: gateway outside rejected" "$(rpc $SID shareos.net set '{"proto":"static","ipaddr":"10.0.0.5","netmask":"255.255.255.0","gateway":"10.0.1.1","confirm":true}')" "'same network' in d['result'][1]['error']"
	t "network: broadcast address rejected" "$(rpc $SID shareos.net set '{"proto":"static","ipaddr":"10.0.0.255","netmask":"255.255.255.0","confirm":true}')" "'broadcast' in d['result'][1]['error']"
	t "network: bad DNS rejected" "$(rpc $SID shareos.net set '{"proto":"static","ipaddr":"10.0.0.5","netmask":"255.255.255.0","dns":["1.2.3"],"confirm":true}')" "'DNS' in d['result'][1]['error']"
	t "network: confirm without change is harmless" "$(rpc $SID shareos.net confirm)" "d['result'][1]['ok']"
	t "GUI assets served" "$(curl -s -o /dev/null -w '{"a":%{http_code},' http://127.0.0.1:$PORT/app.js; curl -s -o /dev/null -w '"c":%{http_code}}' http://127.0.0.1:$PORT/shareos.css)" "d['a']==200 and d['c']==200"
	echo; [ $fails -eq 0 ] && echo "all checks passed" || { echo "$fails check(s) failed"; exit 1; }
	exit 0
fi

echo
echo "ShareOS stack running: http://127.0.0.1:$PORT/  (root / shareos)"
echo "Press Ctrl-C to stop."
while sleep 3600; do :; done
