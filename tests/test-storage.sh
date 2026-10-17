#!/bin/bash
#
# Tests shareos-storage and the shareos.storage rpcd methods with the built
# ARM userland (qemu-user) on loop devices of the build host.
#
#   sudo tests/test-storage.sh [output/dns320l]
#
# Covers the "single" layout, re-setup of a used disk, mount/umount/forget,
# shutdown/boot and the status call. The mirror layout needs the md driver
# in the host kernel and is skipped when /proc/mdstat is missing.
#
set -u
OUT=${1:-output/dns320l}
TOP=$(cd "$(dirname "$0")/.." && pwd)
case "$OUT" in /*) ;; *) OUT="$TOP/$OUT" ;; esac
SQFS="$OUT/images/rootfs.squashfs"
UNSQ="$OUT/host/bin/unsquashfs"
QEMU=$(command -v qemu-arm-static) || { echo "install qemu-user-static"; exit 1; }
[ -f "$SQFS" ] || { echo "no $SQFS"; exit 1; }

T=$(mktemp -d /tmp/shareos-storage-test.XXXX)
R=$T/root
LOOPS=
cleanup() {
	for m in $(grep " $R/" /proc/mounts | awk '{print $2}' | sort -r); do umount -l "$m" 2>/dev/null; done
	for l in $LOOPS; do losetup -d "$l" 2>/dev/null; done
	rm -rf "$T"
}
trap cleanup EXIT

if [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]; then
	[ -e /proc/sys/fs/binfmt_misc/register ] || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
	echo ":qemu-arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:$QEMU:F" \
		> /proc/sys/fs/binfmt_misc/register
fi

"$UNSQ" -q -d "$R" "$SQFS" >/dev/null
mount -t proc proc "$R/proc"
mount -t sysfs sysfs "$R/sys"
mount --bind /dev "$R/dev"
mount -t tmpfs tmpfs "$R/tmp"
mkdir -p "$R/var/run/ubus"

for i in 1 2; do
	truncate -s 300M "$T/disk$i.img"
	l=$(losetup -fP --show "$T/disk$i.img") || { echo "losetup failed"; exit 1; }
	LOOPS="$LOOPS $l"
done
set -- $LOOPS
A=${1#/dev/} B=${2#/dev/}
echo "test disks: $A $B"

run() { chroot "$R" /usr/bin/env SHAREOS_STORAGE_DISKS='loop[0-9]+' /bin/sh -c "$*" 2>&1; }
pass=0; failed=0
check() { if eval "$2"; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; failed=$((failed+1)); fi; }
mounted() { grep -q " $R/mnt/$1 " /proc/mounts; }

o=$(run shareos-storage setup single foo=$A)
check "setup refuses without --yes" "echo \"\$o\" | grep -q 'add --yes'"
o=$(run shareos-storage setup single "BAD=$A" --yes)
check "invalid name rejected" "run shareos-storage job | grep -q 'state=error'"
o=$(run shareos-storage setup single "x=sdz" --yes)
check "unknown disk rejected" "run shareos-storage job | grep -q \"invalid disk\""

o=$(run shareos-storage setup single "daten=$A" "backup=$B" --yes); echo "$o" | sed 's/^/      /'
check "single setup of two disks finished" "run shareos-storage job | grep -q 'state=done'"
check "both volumes mounted" "mounted daten && mounted backup"
check "volumes in UCI with uuid" "run uci get storage.daten.uuid | grep -qE '^[0-9a-f-]{36}$' && run uci get storage.backup.layout | grep -qx single"
check "ext4 label set" "run blkid -s LABEL -o value /dev/${A}p1 | grep -qx daten"
echo hello > "$R/mnt/daten/file"

o=$(run shareos-storage umount daten)
check "umount" "! mounted daten && run uci get storage.daten.enabled | grep -qx 0"
o=$(run shareos-storage mount daten)
check "mount again, data still there" "mounted daten && grep -qx hello $R/mnt/daten/file"

run shareos-storage shutdown >/dev/null
check "shutdown unmounts all" "! mounted daten && ! mounted backup"
run shareos-storage boot >/dev/null
check "boot mounts enabled volumes" "mounted daten && mounted backup"

o=$(run shareos-storage setup single "neu=$B" --yes)
check "re-setup of a used disk releases the old volume" "run shareos-storage job | grep -q 'state=done' && ! run uci -q get storage.backup >/dev/null && mounted neu && ! mounted backup"

o=$(run shareos-storage forget neu)
check "forget removes from config" "! run uci -q get storage.neu >/dev/null && ! mounted neu"
o=$(run shareos-storage spindown 30)
check "spindown stored" "run uci get storage.global.spindown | grep -qx 30"

# rpcd: status call through ubus
run '/usr/sbin/ubusd -s /var/run/ubus/ubus.sock & sleep 1; /sbin/rpcd -s /var/run/ubus/ubus.sock >/dev/null 2>&1 & sleep 2' >/dev/null
S=$(run ubus -s /var/run/ubus/ubus.sock call shareos.storage status)
check "status: volume daten mounted with size" "echo '$S' | python3 -c \"import json,sys; d=json.load(sys.stdin); v=[x for x in d['volumes'] if x['name']=='daten'][0]; sys.exit(0 if v['mounted'] and v['size']>0 and v['layout']=='single' else 1)\""
check "status: job and spindown reported" "echo '$S' | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d['spindown']==30 and d['job']['state']=='done' else 1)\""
E=$(run ubus -s /var/run/ubus/ubus.sock call shareos.storage setup "'{\"layout\":\"mirror\",\"name\":\"x\",\"disks\":[\"sda\",\"sda\"],\"confirm\":true}'")
check "rpc: mirror with the same disk twice rejected" "echo '$E' | grep -q 'two different disks'"
E=$(run ubus -s /var/run/ubus/ubus.sock call shareos.storage setup "'{\"layout\":\"single\",\"volumes\":[{\"name\":\"x\",\"disk\":\"sda\"}]}'")
check "rpc: setup needs confirm" "echo '$E' | grep -q confirm"
E=$(run ubus -s /var/run/ubus/ubus.sock call shareos.storage volume "'{\"name\":\"../etc\",\"action\":\"mount\"}'")
check "rpc: invalid volume name rejected" "echo '$E' | grep -q 'invalid name'"
run 'killall rpcd ubusd' >/dev/null 2>&1

if [ -e /proc/mdstat ]; then
	run shareos-storage setup mirror spiegel $A $B --yes >/dev/null
	check "mirror setup" "run shareos-storage job | grep -q 'state=done' && mounted spiegel && grep -q md /proc/mdstat"
	run shareos-storage shutdown >/dev/null
else
	echo "SKIP  mirror (no md driver on this host)"
fi

echo; echo "$pass passed, $failed failed"
[ $failed -eq 0 ]
