#!/bin/bash
#
# Tests the ShareOS app store (shareos-apps, rpcd shareos.apps, the web server
# for apps) with the built ARM userland (qemu-user) in a chroot. Catalog and
# packages are served from files (file:// is allowed only for this test).
#
#   sudo tests/test-apps.sh [output/dns320l] [webpad.sapp]
#
set -u
OUT=${1:-output/dns320l}
TOP=$(cd "$(dirname "$0")/.." && pwd)
case "$OUT" in /*) ;; *) OUT="$TOP/$OUT" ;; esac
SQFS="$OUT/images/rootfs.squashfs"
UNSQ="$OUT/host/bin/unsquashfs"
QEMU=$(command -v qemu-arm-static) || { echo "install qemu-user-static"; exit 1; }
[ -f "$SQFS" ] || { echo "no $SQFS"; exit 1; }
PORT=${SHAREOS_TEST_APPS_PORT:-18081}

T=$(mktemp -d /tmp/shareos-apps-test.XXXX)
R=$T/root
cleanup() {
	chroot "$R" /bin/sh -c '/etc/init.d/S51apps stop; /etc/init.d/S13rpcd stop; /etc/init.d/S12ubus stop' >/dev/null 2>&1
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
mkdir -p "$R/var/run/ubus" "$R/var/log"

run() { chroot "$R" /usr/bin/env SHAREOS_APPS_ALLOW_FILE=1 /bin/sh -c "$*" 2>&1; }
pass=0; failed=0
check() { if eval "$2"; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; failed=$((failed+1)); fi; }
rpc() { run "ubus call $1 $2 '$3'"; }
js() { python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($1) else 1)"; }

# --- packages: a good one, a bad checksum, path tricks, a link, broken manifest
P=$R/tmp/pkg; mkdir -p $P
mkapp() {   # dir id version [extra python for the manifest]
	mkdir -p "$1/files"
	echo '<!doctype html><title>ok</title>' > "$1/files/index.html"
	python3 - "$1" "$2" "$3" <<'PY'
import json, sys
d, i, v = sys.argv[1:4]
json.dump({"id": i, "name": "Test " + i, "version": v, "publisher": "Test", "type": "webapp", "entry": "index.html",
           "description": {"de": "Test-App", "en": "test app"}}, open(d + "/app.json", "w"))
PY
}
pack() { (cd "$1" && tar -czf "$2" app.json -C files .); }
mkapp $T/a1 hello 1.0.0; pack $T/a1 $P/hello-1.0.0.sapp
mkapp $T/a2 hello 1.1.0; pack $T/a2 $P/hello-1.1.0.sapp
mkapp $T/a3 evil 1.0.0; (cd $T/a3 && tar -czf $P/evil-dots.sapp app.json --transform 's|^|../|' -C files .)
mkapp $T/a4 linky 1.0.0; ln -s /etc/shadow $T/a4/files/shadow; pack $T/a4 $P/linky.sapp
mkapp $T/a5 native 1.0.0; python3 -c "import json; f='$T/a5/app.json'; d=json.load(open(f)); d['type']='native'; json.dump(d,open(f,'w'))"; pack $T/a5 $P/native.sapp
mkapp $T/a6 noentry 1.0.0; rm $T/a6/files/index.html; echo x > $T/a6/files/other.html; pack $T/a6 $P/noentry.sapp
[ -n "${2:-}" ] && [ -f "$2" ] && cp "$2" $P/webpad.sapp
sha() { sha256sum "$1" | cut -d' ' -f1; }
python3 - "$P" "$(sha $P/hello-1.0.0.sapp)" "$(sha $P/hello-1.1.0.sapp)" <<'PY' > $P/index.json
import json, sys
p, s1, s2 = sys.argv[1:4]
v = lambda ver, f, s, pre=False: {"version": ver, "date": "2026-10-18T10:00:00Z", "prerelease": pre, "url": "file:///tmp/pkg/" + f, "sha256": s, "size": 100, "min_shareos": "0.0"}
print(json.dumps({"schema": 1, "apps": [
  {"id": "hello", "name": "Hello", "publisher": "Test", "type": "webapp", "versions": [v("1.0.0", "hello-1.0.0.sapp", s1), v("1.1.0", "hello-1.1.0.sapp", s2, True)]},
  {"id": "broken", "name": "Broken", "publisher": "Test", "type": "webapp", "versions": [v("1.0.0", "hello-1.0.0.sapp", "0" * 64)]},
  {"id": "insecure", "name": "Insecure", "publisher": "Test", "versions": [dict(v("1.0.0", "x", s1), url="http://example.com/x.sapp")]}]}))
PY
run "uci -q delete apps.store.source; uci add_list apps.store.source=file:///tmp/pkg/index.json; uci set apps.store.port=$PORT; uci set apps.store.https_port=$((PORT+1)); uci set shareos.web.https=0; uci commit apps; uci commit shareos" >/dev/null

C=$(run "shareos-apps catalog")
check "catalog: stable channel shows release versions only" "echo '$C' | js \"[(a['id'],a['latest']) for a in d['apps']]==[('broken','1.0.0'),('hello','1.0.0')]\""
check "catalog: plain http package URLs are ignored" "! echo '$C' | grep -q insecure"
run "uci set apps.store.channel=beta; uci commit apps" >/dev/null
check "catalog: beta channel offers the pre-release" "run 'shareos-apps cached' | js \"[a['latest'] for a in d['apps'] if a['id']=='hello']==['1.1.0']\""
run "uci set apps.store.channel=stable; uci commit apps" >/dev/null
check "install from the catalog (checksum verified)" "run 'shareos-apps install hello' | js \"d['ok'] and d['version']=='1.0.0' and d['verified']\" && [ -f $R/www-apps/hello/index.html ] && [ -f $R/www-apps/hello/app.json ]"
check "installed list" "run 'shareos-apps list' | js \"[(a['id'],a['version'],a['verified'],a['users']) for a in d['apps']]==[('hello','1.0.0',True,['*'])]\""
check "update offered after switching to beta" "run 'uci set apps.store.channel=beta; uci commit apps; shareos-apps cached' | js \"[a['update_available'] for a in d['apps'] if a['id']=='hello']==[True]\""
check "update installs the new version" "run 'shareos-apps install hello 1.1.0' | js \"d['version']=='1.1.0'\" && run 'shareos-apps list' | js \"d['apps'][0]['version']=='1.1.0'\""
check "wrong checksum: not installed" "run 'shareos-apps install broken' | grep -q 'checksum mismatch' && [ ! -d $R/www-apps/broken ]"
check "job status after an install" "run 'shareos-apps status' | js \"d['state'] in ('done','error')\""
check "package with ../ paths rejected" "run 'shareos-apps install-file /tmp/pkg/evil-dots.sapp' | grep -q 'unsafe path' && [ ! -e $R/www-apps/evil ] && [ ! -e $R/evil ]"
check "package with a symlink rejected" "run 'shareos-apps install-file /tmp/pkg/linky.sapp' | grep -q 'links' && [ ! -e $R/www-apps/linky ]"
check "native apps are refused (not supported yet)" "run 'shareos-apps install-file /tmp/pkg/native.sapp' | grep -q 'not supported'"
check "missing entry file rejected" "run 'shareos-apps install-file /tmp/pkg/noentry.sapp' | grep -q 'entry file' && [ ! -e $R/www-apps/noentry ]"
check "no leftovers from failed installs" "[ -z \"\$(ls -A $R/www-apps | grep '^\.new')\" ]"
if [ -f $P/webpad.sapp ]; then
	check "Webpad package from the app repo installs (own upload)" "run 'shareos-apps install-file /tmp/pkg/webpad.sapp' | js \"d['id']=='webpad' and not d['verified']\" && [ -f $R/www-apps/webpad/vendor/codemirror/lib/codemirror.js ]"
fi

# --- web server for apps and rpcd
run '/etc/init.d/S12ubus start && /etc/init.d/S13rpcd start && /etc/init.d/S51apps start' >/dev/null
i=0; until curl -s -o /dev/null "http://127.0.0.1:$PORT/" || [ $i -ge 30 ]; do sleep 0.5; i=$((i + 1)); done
check "apps are served on their own port" "[ \"\$(curl -s http://127.0.0.1:$PORT/hello/index.html)\" = '<!doctype html><title>ok</title>' ]"
check "app server has no /ubus (no admin login there)" "[ \"\$(curl -s -o /dev/null -w '%{http_code}' -d '{}' http://127.0.0.1:$PORT/ubus)\" != 200 ]"
check "app server root leads to the admin interface" "curl -s http://127.0.0.1:$PORT/ | grep -q '#/apps'"
check "app server: no directory listing" "! curl -s http://127.0.0.1:$PORT/hello/ | grep -qi 'index of'"
i=0; until run "ubus list shareos.apps" >/dev/null 2>&1 || [ $i -ge 30 ]; do sleep 0.5; i=$((i + 1)); done
check "rpc: installed with server ports" "rpc shareos.apps installed '{}' | js \"d['port']==$PORT and [a['id'] for a in d['apps']][0]=='hello'\""
check "rpc: store sources must be https" "rpc shareos.apps store_set '{\"sources\":[\"http://x/index.json\"]}' | grep -q 'https'"
check "rpc: unknown user in visibility rejected" "rpc shareos.apps set '{\"id\":\"hello\",\"users\":[\"ghost\"]}' | grep -q 'unknown user'"
mkdir -p "$R/mnt/daten"; run "uci set storage.daten=volume; uci commit storage; echo lisa1234 | shareos-users add lisa user; echo bert1234 | shareos-users add bert user" >/dev/null
check "rpc: visibility per user" "rpc shareos.apps set '{\"id\":\"hello\",\"users\":[\"lisa\"]}' | js \"d['ok']\""
L1=$(rpc session login '{"username":"lisa","password":"lisa1234"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["ubus_rpc_session"])')
L2=$(rpc session login '{"username":"bert","password":"bert1234"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["ubus_rpc_session"])')
check "allowed user sees the app in My ShareOS" "rpc shareos.me bind '{\"username\":\"lisa\",\"password\":\"lisa1234\",\"ubus_rpc_session\":\"$L1\"}' | js \"'hello' in [a['id'] for a in d['apps']] and d['apps_server']['port']==$PORT\""
check "other users do not" "rpc shareos.me bind '{\"username\":\"bert\",\"password\":\"bert1234\",\"ubus_rpc_session\":\"$L2\"}' | js \"'hello' not in [a['id'] for a in d['apps']]\""
TK=$(rpc shareos.apps upload_ticket '{}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"].split("t=")[1])')
cp $P/hello-1.0.0.sapp $R/tmp/up.sapp
o=$(run "QUERY_STRING=t=$TK REQUEST_METHOD=POST CONTENT_LENGTH=$(stat -c %s $R/tmp/up.sapp) /www/cgi-bin/files < /tmp/up.sapp")
check "upload a package through the CGI and install it" "echo \"\$o\" | grep -q 'Status: 200' && rpc shareos.apps install_upload '{}' | js \"d['id']=='hello' and d['version']=='1.0.0' and not d['verified']\""
check "users stay after reinstalling" "run 'shareos-apps list' | js \"d['apps'][0]['users']==['lisa']\""
check "remove" "rpc shareos.apps remove '{\"id\":\"hello\"}' | js \"d['ok']\" && [ ! -e $R/www-apps/hello ] && ! run 'uci -q get apps.app_hello' | grep -q app"
check "invalid id rejected" "rpc shareos.apps remove '{\"id\":\"../etc\"}' | grep -q 'invalid'"

echo; echo "$pass passed, $failed failed"
[ $failed -eq 0 ]
