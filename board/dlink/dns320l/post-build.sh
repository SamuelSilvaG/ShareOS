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
SHAREOS_FWNAME="DNS-320L-rev-Ax"
SHAREOS_STAGE="dev"
EOF

# All kernel modules stay in the squashfs root; the small initramfs needs
# none (UBI, UBIFS, squashfs and overlayfs are built into the kernel).

# The UBI installer is part of both the initramfs and the full system
install -D -m 0755 "$BOARD_DIR/initramfs/usr/sbin/shareos-install-ubi" "$TARGET_DIR/usr/sbin/shareos-install-ubi"

# Nothing in the test system needs these
rm -rf "$TARGET_DIR/usr/share/man" "$TARGET_DIR/usr/share/doc" \
	"$TARGET_DIR/usr/lib/pkgconfig" "$TARGET_DIR/usr/include"
