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
CPIO="$OUT/images/rootfs.cpio"
[ -f "$CPIO" ] || { echo "no $CPIO – build first (make dns320l)"; exit 1; }
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

(cd "$R" && cpio -id --quiet < "$CPIO")
mkdir -p "$R/proc" "$R/dev"
mount -t proc proc "$R/proc"
mount --bind /dev "$R/dev"
sed -i "s/-p 80 /-p $PORT /" "$R/etc/init.d/S50uhttpd"

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
	echo; [ $fails -eq 0 ] && echo "all checks passed" || { echo "$fails check(s) failed"; exit 1; }
	exit 0
fi

echo
echo "ShareOS stack running: http://127.0.0.1:$PORT/  (root / shareos)"
echo "Press Ctrl-C to stop."
while sleep 3600; do :; done
