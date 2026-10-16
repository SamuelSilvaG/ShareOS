#!/bin/bash
#
# ShareOS post-build (DNS-320L), runs before the rootfs images are made.
# $1 = TARGET_DIR
#
set -e

TARGET_DIR="$1"
BOARD_DIR="$(dirname "$0")"
TOP_DIR="$(cd "$BOARD_DIR/../../.." && pwd)"

VERSION="$("$TOP_DIR/scripts/version.sh")"

cat > "$TARGET_DIR/etc/shareos-release" <<EOF
SHAREOS_VERSION="$VERSION"
SHAREOS_BOARD="dns320l"
SHAREOS_STAGE="phase1-test"
EOF

# Kernel modules: the 'ramdisk' partition is limited to 3 MB by the stock
# U-Boot, so only the modules the test system needs stay in the initramfs
# (plus their dependencies). All modules are packed separately and will
# live in the UBI image (phase 3).
KEEP_MODULES="ehci-orion usb-storage ext4"

MODDIR=$(ls -d "$TARGET_DIR"/lib/modules/* 2>/dev/null | head -1)
if [ -n "$MODDIR" ]; then
	tar -C "$TARGET_DIR" -cJf "$BINARIES_DIR/modules.tar.xz" lib/modules
	KDIR=$(mktemp -d)
	(cd "$MODDIR" && cp -a modules.* "$KDIR"/)
	# resolve dependencies through modules.dep
	need=""
	for m in $KEEP_MODULES; do
		line=$(grep -E "(^|/)${m//-/[-_]}\.ko(\.[a-z]+)?:" "$MODDIR/modules.dep" || true)
		[ -n "$line" ] || { echo "post-build: module $m not found" >&2; continue; }
		need="$need ${line%%:*} ${line#*:}"
	done
	for f in $(echo $need | tr ' ' '\n' | sort -u); do
		mkdir -p "$KDIR/$(dirname "$f")"
		cp -a "$MODDIR/$f" "$KDIR/$f"
	done
	rm -rf "$MODDIR"
	mv "$KDIR" "$MODDIR"
	chmod 755 "$MODDIR"
	echo "post-build: modules kept in initramfs:"; find "$MODDIR" -name "*.ko*" -printf "  %P\n"
fi

# Nothing in the test system needs these
rm -rf "$TARGET_DIR/usr/share/man" "$TARGET_DIR/usr/share/doc" \
	"$TARGET_DIR/usr/lib/pkgconfig" "$TARGET_DIR/usr/include"
