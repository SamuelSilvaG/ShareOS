#!/bin/bash
#
# ShareOS post-image (DNS-320L): builds the firmware file in the D-Link
# container format, flashable / "TryIt"-able from the stock web UI, Alt-F
# and ShareOS. Replaces Alt-F's mkfw.sh for this board.
#
# Layout and limits (stock U-Boot, see legacy/alt-f/mkfw.sh NOTE-2):
#   uImage  partition 5 MB, U-Boot reads 0x300000 -> uImage   <= 3145728
#   ramdisk partition 5 MB, U-Boot reads 0x300000 -> urootfs  <= 3145728
#
set -euo pipefail

BOARD_DIR="$(dirname "$0")"
TOP_DIR="$(cd "$BOARD_DIR/../../.." && pwd)"
B="$BINARIES_DIR"
MKIMAGE="$HOST_DIR/bin/mkimage"
FW="$HOST_DIR/bin/dns323-fw"

VERSION="$("$TOP_DIR/scripts/version.sh")"
NAME="DNS-320L-rev-Ax"
OUT="ShareOS-${VERSION}-${NAME}.bin"

KERNEL_MAX=3145728
INITRD_MAX=3145728

# D-Link signature for the DNS-320L rev A (legacy/alt-f/mkfw.sh index 8)
PROD=0 CUST=8 MODEL=11 SUB=1 NVER=1 TYPE=6

ZIMAGE="$B/zImage.kirkwood-dns320l"     # zImage with appended DTB
[ -f "$ZIMAGE" ] || { echo "post-image: $ZIMAGE missing"; exit 1; }

KVER=$(sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="\(.*\)"/\1/p' "$BR2_CONFIG")

# small initramfs (rescue system + UBI loader) for the 'ramdisk' partition
"$BOARD_DIR/mk-initramfs.sh" "$TARGET_DIR" "$B" "$HOST_DIR" "$BOARD_DIR"
[ -s "$B/rootfs.squashfs" ] || { echo "post-image: rootfs.squashfs missing"; exit 1; }

"$MKIMAGE" -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 \
	-n "ShareOS-${VERSION}, kernel ${KVER}" -d "$ZIMAGE" "$B/uImage"

"$MKIMAGE" -A arm -O linux -T ramdisk -C none -a 0x00800000 -e 0x00800000 \
	-n "ShareOS-${VERSION}, initrd" -d "$B/initramfs.cpio.xz" "$B/urootfs"

check_size() {
	local f=$1 max=$2 sz
	sz=$(stat -c %s "$f")
	if [ "$sz" -gt "$max" ]; then
		echo "post-image: $(basename "$f") is $sz bytes, too big by $((sz - max)) (max $max)" >&2
		exit 1
	fi
	echo "post-image: $(basename "$f") $sz bytes, $((max - sz)) bytes free"
}
check_size "$B/uImage" $KERNEL_MAX
check_size "$B/urootfs" $INITRD_MAX

rm -f "$B/$OUT"
"$FW" -m -q -p $PROD -c $CUST -l $MODEL -u $SUB -v $NVER -t $TYPE \
	-k "$B/uImage" -i "$B/urootfs" "$B/$OUT"

# verify: split again and compare with the parts
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
"$FW" -s -q -k "$T/kernel" -i "$T/initramfs" "$B/$OUT"
cmp "$T/kernel" "$B/uImage"
cmp "$T/initramfs" "$B/urootfs"
"$MKIMAGE" -l "$T/kernel" >/dev/null
"$MKIMAGE" -l "$T/initramfs" >/dev/null

(cd "$B" && sha256sum "$OUT" > "$OUT.sha256")
# Alt-F's firmware page accepts an optional *.sha1 file next to the .bin
(cd "$B" && sha1sum "$OUT" > "${OUT%.bin}.sha1")
"$FW" -f "$B/$OUT" || true
echo "post-image: created $B/$OUT"

# netboot bundle: everything needed to run this build from RAM via TFTP
# (U-Boot loads uImage + urootfs, the initramfs fetches rootfs.squashfs)
NB="shareos-netboot-${VERSION}.tar"
(cd "$B" && sha256sum uImage urootfs rootfs.squashfs > SHA256SUMS-netboot \
	&& tar -cf "$NB" --transform 's/SHA256SUMS-netboot/SHA256SUMS/' uImage urootfs rootfs.squashfs SHA256SUMS-netboot)
echo "post-image: created $B/$NB"
echo "post-image: rootfs.squashfs $(stat -c %s "$B/rootfs.squashfs") bytes (UBI volume 'rootfs')"
