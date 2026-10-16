#!/bin/sh
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

# Kernel modules do not go into the initramfs: the 'ramdisk' partition is
# limited to 3 MB by the stock U-Boot. They are packed separately and will
# live in the UBI image (phase 3).
if [ -d "$TARGET_DIR/lib/modules" ]; then
	tar -C "$TARGET_DIR" -cJf "$BINARIES_DIR/modules.tar.xz" lib/modules
	rm -rf "$TARGET_DIR/lib/modules"
fi

# Nothing in the test system needs these
rm -rf "$TARGET_DIR/usr/share/man" "$TARGET_DIR/usr/share/doc" \
	"$TARGET_DIR/usr/lib/pkgconfig" "$TARGET_DIR/usr/include"
