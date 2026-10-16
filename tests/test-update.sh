#!/bin/bash
#
# Host test for shareos-update against a mock GitHub API.
#
#   tests/test-update.sh <ucode-binary> <firmware.bin|--synthetic> [dns323-fw]
#
# Needs: python3, curl, sha256sum; ucode built with fs + uci modules.
# --synthetic builds a small DNS-320L container with mkimage + dns323-fw,
# so the test does not need a full firmware build (used in CI).
#
set -u
UCODE=${1:?ucode binary}
FW=${2:?firmware .bin built for DNS-320L, or --synthetic}
DNSFW=${3:-dns323-fw}
DNSFW=$(realpath "$(command -v "$DNSFW")")
TOP=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$TOP/src/shareos-core/usr/sbin/shareos-update"

[ "$FW" = "--synthetic" ] || FW=$(realpath "$FW")
T=$(mktemp -d)
cd "$T"          # dns323-fw drops helper files into the working directory
SRV=
trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT

if [ "$FW" = "--synthetic" ]; then
	mkdir -p $T/fw
	head -c 1500000 /dev/urandom > $T/fw/zImage
	head -c 900000 /dev/urandom > $T/fw/initrd
	mkimage -A arm -O linux -T kernel -C none -a 0x8000 -e 0x8000 -n test -d $T/fw/zImage $T/fw/uImage >/dev/null
	mkimage -A arm -O linux -T ramdisk -C none -a 0x800000 -e 0x800000 -n test -d $T/fw/initrd $T/fw/urootfs >/dev/null
	"$DNSFW" -m -q -p 0 -c 8 -l 11 -u 1 -v 1 -t 6 -k $T/fw/uImage -i $T/fw/urootfs $T/fw/test.bin
	FW=$T/fw/test.bin
fi
ROOT=$T/root
WEB=$T/web
PORT=$((20000 + RANDOM % 10000))
API="http://127.0.0.1:$PORT"

# --- fake box -----------------------------------------------------------------
mkdir -p $ROOT/etc/config $ROOT/tmp $ROOT/proc/device-tree $T/bin
cp "$TOP/src/shareos-core/etc/config/shareos" $ROOT/etc/config/
sed -i "s|option api .*|option api '$API'|" $ROOT/etc/config/shareos
cat > $ROOT/etc/shareos-release <<EOF
SHAREOS_VERSION="0.0-20261016-test"
SHAREOS_BOARD="dns320l"
SHAREOS_FWNAME="DNS-320L-rev-Ax"
EOF
printf 'Some Other Board\0' > $ROOT/proc/device-tree/model
ln -s "$DNSFW" $T/bin/dns323-fw

# --- fake GitHub ---------------------------------------------------------------
mkdir -p $WEB/repos/UniqueDroid/ShareOS $WEB/dl
cp "$FW" $WEB/dl/ShareOS-0.1.0-DNS-320L-rev-Ax.bin
(cd $WEB/dl && sha256sum ShareOS-0.1.0-DNS-320L-rev-Ax.bin > ShareOS-0.1.0-DNS-320L-rev-Ax.bin.sha256)
cp "$FW" $WEB/dl/ShareOS-0.2.0-beta.1-DNS-320L-rev-Ax.bin
(cd $WEB/dl && sha256sum ShareOS-0.2.0-beta.1-DNS-320L-rev-Ax.bin > ShareOS-0.2.0-beta.1-DNS-320L-rev-Ax.bin.sha256)
# valid checksum, but a DNS-325 container (signature check must refuse it)
"$DNSFW" -m -q -p 0 -c 8 -l 5 -u 2 -v 0 -t 3 -k "$(dirname "$FW")/uImage" -i "$(dirname "$FW")/urootfs" $WEB/dl/ShareOS-0.1.1-DNS-320L-rev-Ax.bin
(cd $WEB/dl && sha256sum ShareOS-0.1.1-DNS-320L-rev-Ax.bin > ShareOS-0.1.1-DNS-320L-rev-Ax.bin.sha256)
# corrupted: checksum does not match
cp "$FW" $WEB/dl/ShareOS-0.0.9-DNS-320L-rev-Ax.bin
echo "0000000000000000000000000000000000000000000000000000000000000000  x" > $WEB/dl/ShareOS-0.0.9-DNS-320L-rev-Ax.bin.sha256

asset() { printf '{"name":"%s","size":%d,"browser_download_url":"%s/dl/%s"}' "$1" "$(stat -c %s $WEB/dl/$1)" "$API" "$1"; }
cat > $WEB/repos/UniqueDroid/ShareOS/releases <<EOF
[
 {"tag_name":"v0.3.0","draft":true,"prerelease":false,"assets":[]},
 {"tag_name":"v0.2.0-beta.1","draft":false,"prerelease":true,"published_at":"2026-10-20T10:00:00Z","body":"beta",
  "assets":[$(asset ShareOS-0.2.0-beta.1-DNS-320L-rev-Ax.bin),$(asset ShareOS-0.2.0-beta.1-DNS-320L-rev-Ax.bin.sha256)]},
 {"tag_name":"v0.1.1","draft":false,"prerelease":false,"published_at":"2026-10-19T10:00:00Z","body":"wrong box",
  "assets":[$(asset ShareOS-0.1.1-DNS-320L-rev-Ax.bin),$(asset ShareOS-0.1.1-DNS-320L-rev-Ax.bin.sha256)]},
 {"tag_name":"v0.1.0","draft":false,"prerelease":false,"published_at":"2026-10-18T10:00:00Z","body":"first release",
  "assets":[$(asset ShareOS-0.1.0-DNS-320L-rev-Ax.bin),$(asset ShareOS-0.1.0-DNS-320L-rev-Ax.bin.sha256)]},
 {"tag_name":"v0.0.9","draft":false,"prerelease":false,"published_at":"2026-10-17T10:00:00Z","body":"broken",
  "assets":[$(asset ShareOS-0.0.9-DNS-320L-rev-Ax.bin),$(asset ShareOS-0.0.9-DNS-320L-rev-Ax.bin.sha256)]},
 {"tag_name":"v0.0.8","draft":false,"prerelease":false,"assets":[{"name":"ShareOS-0.0.8-DNS-325-rev-Ax.bin","size":1,"browser_download_url":"x"}]}
]
EOF
(cd $WEB && exec python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) &
SRV=$!
for i in $(seq 50); do curl -s -o /dev/null $API/ && break; sleep 0.1; done

# --- runner -------------------------------------------------------------------
pass=0; failed=0
run() { PATH="$T/bin:$PATH" SHAREOS_ROOT=$ROOT "$UCODE" -S "$SCRIPT" "$@" 2>&1; }
check() { # name, json-output, python expression on d
	if printf '%s' "$2" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if ($3) else 1)" 2>/dev/null; then
		echo "PASS  $1"; pass=$((pass+1))
	else
		echo "FAIL  $1"; echo "      output: $2"; failed=$((failed+1))
	fi
}

o=$(run check);          check "check stable: newest is v0.1.1, drafts/betas/other boards hidden" "$o" \
	"d['latest']=='v0.1.1' and [r['tag'] for r in d['releases']]==['v0.1.1','v0.1.0','v0.0.9'] and d['update_available']"
o=$(run check beta);     check "check beta: v0.2.0-beta.1 first" "$o" \
	"d['latest']=='v0.2.0-beta.1' and len(d['releases'])==4"
o=$(run download v9.9);  check "download unknown tag is rejected" "$o" "d['state']=='error' and 'unknown release' in d['error']"
o=$(run download v0.1.1);check "firmware for another box is rejected (signature)" "$o" "d['state']=='error' and 'DNS320L' in d['error']"
o=$(run download v0.0.9);check "corrupted image is rejected (SHA-256)" "$o" "d['state']=='error' and 'SHA-256' in d['error']"
o=$(run download v0.2.0-beta.1); check "download + verify beta" "$o" "d['state']=='ready' and d['release']['tag']=='v0.2.0-beta.1'"
o=$(run status);         check "status reports ready" "$o" "d['state']=='ready' and d['current']=='0.0-20261016-test'"
o=$(run apply v0.1.0);   check "apply of a different tag is refused" "$o" "d['state']=='error' and 'not downloaded' in d['error']"
run download v0.2.0-beta.1 >/dev/null
o=$(run apply v0.2.0-beta.1); check "apply refuses on a non-DNS-320L board" "$o" "d['state']=='error' and 'unexpected board' in d['error']"
o=$(run cancel);         check "cancel resets the state" "$o" "d['state']=='idle'"

echo; echo "$pass passed, $failed failed"
[ $failed -eq 0 ]
