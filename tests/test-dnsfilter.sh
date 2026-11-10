#!/bin/bash
#
# Tests the DNS filter module: system app "dnsfilter" (AdGuard Home), shareos-
# dnsfilter, rpcd shareos.dnsfilter – built ARM userland (qemu-user) in a
# chroot, an apps drive, a block list served from the host. AdGuard Home
# binds port 53 and the given web port on the host (it shares the network).
#
#   sudo tests/test-dnsfilter.sh [output/dns320l] [dnsfilter.sapp]   (make sysapps-pack)
#
[ -n "${SHAREOS_TEST_UTS:-}" ] || exec unshare --uts env SHAREOS_TEST_UTS=1 "$0" "$@"
set -u
OUT=${1:-output/dns320l}
TOP=$(cd "$(dirname "$0")/.." && pwd)
case "$OUT" in /*) ;; *) OUT="$TOP/$OUT" ;; esac
SQFS="$OUT/images/rootfs.squashfs"
UNSQ="$OUT/host/bin/unsquashfs"
QEMU=$(command -v qemu-arm-static) || { echo "install qemu-user-static"; exit 1; }
[ -f "$SQFS" ] || { echo "no $SQFS"; exit 1; }
SAPP=${2:-$(ls -t "$TOP"/output/sysapps/sapp/dnsfilter-*.sapp 2>/dev/null | head -1)}
[ -f "$SAPP" ] || { echo "no dnsfilter .sapp – make sysapps-pack"; exit 1; }
LPORT=18977

T=$(mktemp -d /tmp/shareos-dnsfilter-test.XXXX)
R=$T/root
SRV=
cleanup() {
	[ -n "$SRV" ] && kill "$SRV" 2>/dev/null
	chroot "$R" /bin/sh -c '/usr/sbin/shareos-dnsfilter stop-all; /etc/init.d/S13rpcd stop; /etc/init.d/S12ubus stop' >/dev/null 2>&1
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
# testing a changed controller with an older image: SHAREOS_TEST_CONTROLLER=<file>
[ -n "${SHAREOS_TEST_CONTROLLER:-}" ] && cp "$SHAREOS_TEST_CONTROLLER" "$R/usr/sbin/shareos-dnsfilter"
mount -t proc proc "$R/proc"
mount --bind /dev "$R/dev"
mount -t tmpfs tmpfs "$R/tmp"
mkdir -p "$R/var/run/ubus" "$R/var/log" "$R/etc/crontabs" "$T/drive" "$R/mnt/daten"
# the apps drive: a folder of the host, mounted so that /proc/mounts lists it
mount --bind "$T/drive" "$R/mnt/daten"
mkdir -p "$R/mnt/daten/.shareos"

run() { chroot "$R" /bin/sh -c "$*" 2>&1; }
pass=0; failed=0
check() { if eval "$2"; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; failed=$((failed+1)); fi; }
js() { python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($1) else 1)"; }
df() { run "echo '${2:-}' | shareos-dnsfilter $1"; }
ub() { local a=${2:-'{}'}; run "ubus call shareos.dnsfilter $1 '$a'"; }
# a DNS query to the box: prints the first IPv4 address of the answer (or rc=<rcode>)
dnsq() {
	python3 - "$1" <<'EOF'
import socket, struct, sys
name = sys.argv[1]
q = struct.pack('>HHHHHH', 0x1234, 0x100, 1, 0, 0, 0) + b''.join(bytes([len(p)]) + p.encode() for p in name.split('.')) + b'\0\0\1\0\1'
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(8)
s.sendto(q, ('127.0.0.1', 53))
try: r = s.recv(1024)
except Exception: print('timeout'); sys.exit()
rc, an = r[3] & 15, struct.unpack('>H', r[6:8])[0]
if not an: print('rc=%d' % rc); sys.exit()
i = len(q)
for _ in range(an):
	i += 2; t, c, ttl, l = struct.unpack('>HHIH', r[i:i + 10]); i += 10
	if t == 1: print('.'.join(str(b) for b in r[i:i + 4])); sys.exit()
	i += l
print('rc=%d' % rc)
EOF
}
wait_ready() { i=0; until ub status | js "d.get('ready')" || [ $i -ge ${1:-120} ]; do sleep 1; i=$((i + 1)); done; }

# a block list on the host
mkdir -p "$T/www"
printf '# test list\n0.0.0.0 ads.shareos-test.example\n0.0.0.0 tracker.shareos-test.example\n||banner.shareos-test.example^\n' > "$T/www/list.txt"
(cd "$T/www" && exec python3 -m http.server $LPORT --bind 127.0.0.1 >/dev/null 2>&1) & SRV=$!

run 'uci set storage.global=storage; uci set storage.global.apps=daten; uci commit storage' >/dev/null
run '/etc/init.d/S12ubus start && /etc/init.d/S13rpcd start' >/dev/null
i=0; until run 'ubus list shareos.dnsfilter' | grep -q dnsfilter || [ $i -ge 40 ]; do sleep 0.5; i=$((i + 1)); done

# --- module ------------------------------------------------------------------------
check "not installed: rpc refused" "ub status | grep -q 'not installed'"
check "not installed: no tab" "run 'ubus call shareos.ui get' | js \"d['areas']['dnsfilter']==False\""
cp "$SAPP" "$R/tmp/dnsfilter.sapp"
check "installed from its package (module)" "run 'shareos-apps install-file /tmp/dnsfilter.sapp' | js \"d['ok'] and d['module']\""
check "tab once installed" "run 'ubus call shareos.ui get' | js \"d['areas']['dnsfilter']==True\""
check "listed as module and service" "run 'shareos-apps modules' | js \"'dnsfilter' in d['modules']\" && run 'shareos-apps services list' | grep -q dnsfilter"
check "off after installing" "ub status | js \"d['installed'] and not d['enabled'] and not d['running']\""
check "boot does nothing while off" "df boot | js \"d.get('started')==False\""

# --- first start ----------------------------------------------------------------------
check "switch on: starts in the background" "ub set '{\"enabled\":true}' | js \"d.get('ok')\""
wait_ready 180
check "first start: running and ready" "ub status | js \"d['ready'] and d['web_port']==8053 and d['version']\""
Y=$R/etc/shareos/dnsfilter/AdGuardHome.yaml
check "settings written by AdGuard's setup" "grep -q '^schema_version:' $Y && grep -q 'address: 0.0.0.0:8053' $Y"
check "guard rail: query log in RAM, no file" "grep -A8 '^querylog:' $Y | grep -q 'file_enabled: false' && grep -A8 '^querylog:' $Y | grep -q 'dir_path: /tmp/shareos-dnsfilter/data'"
check "guard rail: statistics in RAM" "grep -A3 '^statistics:' $Y | grep -q 'dir_path: /tmp/shareos-dnsfilter/data'"
P=$(cat $R/tmp/shareos-dnsfilter/pid)
check "guard rail: GOMEMLIMIT set" "tr '\0' '\n' < $R/proc/$P/environ | grep -q '^GOMEMLIMIT=32MiB$'"
check "password: random, root only" "[ \"\$(stat -c %a $R/etc/shareos/dnsfilter.pass)\" = 600 ] && ub password | js \"d['user']=='admin' and len(d['password'])==20\""
PW=$(ub password | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
check "AdGuard's interface: login with that password" "curl -s -o /dev/null -w '%{http_code}' -u admin:$PW http://127.0.0.1:8053/control/status | grep -q 200"
check "AdGuard's interface: wrong password refused" "curl -s -o /dev/null -w '%{http_code}' -u admin:wrong http://127.0.0.1:8053/control/status | grep -q 401"
check "lists: the default lists of AdGuard" "ub filters | js \"len(d['filters'])>=1\""

# --- block lists ----------------------------------------------------------------------
check "list added" "ub filter_add '{\"name\":\"Test\",\"url\":\"http://127.0.0.1:$LPORT/list.txt\"}' | js \"[f for f in d['filters'] if f['name']=='Test' and f['rules']==3]\""
check "blocked name answered with 0.0.0.0" "[ \"\$(dnsq ads.shareos-test.example)\" = 0.0.0.0 ] && [ \"\$(dnsq banner.shareos-test.example)\" = 0.0.0.0 ]"
check "status: rules, queries, blocked, estimate" "ub status | js \"d['rules']>=3 and d['blocked']>=2 and d['queries']>=2 and d['estimate_mb']>=25 and not d['warn']\""
check "list switched off: name no longer blocked" "ub filter_enable '{\"url\":\"http://127.0.0.1:$LPORT/list.txt\",\"enabled\":false}' | js \"[f for f in d['filters'] if f['name']=='Test' and not f['enabled']]\" && [ \"\$(dnsq tracker.shareos-test.example)\" != 0.0.0.0 ]"
check "list removed" "ub filter_remove '{\"url\":\"http://127.0.0.1:$LPORT/list.txt\"}' | js \"not [f for f in d['filters'] if f['name']=='Test']\""
check "invalid list address refused" "ub filter_add '{\"name\":\"x\",\"url\":\"file:///etc/shadow\"}' | grep -q 'http(s) address'"
check "lists refreshed" "ub refresh | js \"'filters' in d\""

# --- settings -------------------------------------------------------------------------
check "upstream set" "ub set '{\"upstream\":[\"https://dns.quad9.net/dns-query\",\"1.1.1.1\"]}' | js \"d['upstream']==['https://dns.quad9.net/dns-query','1.1.1.1']\""
check "invalid upstream refused" "ub set '{\"upstream\":[\"rm -rf /\"]}' | grep -q 'invalid upstream'"
check "port of the box refused" "ub set '{\"web_port\":443}' | grep -q 'not a port of the box'"
check "filtering paused and on again" "ub set '{\"protection\":false}' | js \"d['protection']==False\" && ub set '{\"protection\":true}' | js \"d['protection']==True\""
check "web port changed: restarted on the new port" "ub set '{\"web_port\":8063}' | js \"d['ready'] and d['web_port']==8063\" && curl -s -o /dev/null -w '%{http_code}' -u admin:$PW http://127.0.0.1:8063/control/status | grep -q 200"
check "settings kept over a restart" "df restart | js \"d['ready'] and d['upstream'][0]=='https://dns.quad9.net/dns-query'\""

# --- switching off, boot, removal -------------------------------------------------------
check "switched off: stopped" "ub set '{\"enabled\":false}' | js \"not d['running'] and not d['enabled']\" && [ \"\$(dnsq ads.shareos-test.example)\" = timeout ]"
check "boot while off: not started" "df boot | js \"d.get('started')==False\""
run "uci set dnsfilter.main.enabled=1; uci commit dnsfilter" >/dev/null
o=$(df boot)
check "boot while on: started" "echo \"\$o\" | js \"d.get('ready')\" || { echo \"\$o\"; false; }"
check "removed: stopped, tab gone, settings kept" "run 'shareos-apps remove dnsfilter' >/dev/null; ! [ -e $R/tmp/shareos-dnsfilter/pid ] && run 'ubus call shareos.ui get' | js \"d['areas']['dnsfilter']==False\" && [ -f $Y ]"

echo
echo "$pass passed, $failed failed"
[ $failed -eq 0 ]
