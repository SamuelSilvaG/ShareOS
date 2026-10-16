#!/bin/sh
#
# ShareOS – start the test system from a running Alt-F WITHOUT flashing.
#
# Run on the Alt-F box (busybox sh), from the unpacked test bundle:
#   sh shareos-kexec-test.sh            kernel messages to the LAN broadcast
#   sh shareos-kexec-test.sh <pc-ip>    kernel messages to one PC
#
# What it does (all in RAM, gone after the next power cycle):
#   - puts kernel, device tree, initramfs and a command line into /boot,
#     which Alt-F's shutdown script (rcE) then starts with kexec
#     (the same thing the "TryIt" button does on other boxes)
#   - enables netconsole: kernel messages go via UDP port 6666 to the PC
#   - takes eth0 down before the jump (DMA from an active NIC can corrupt
#     the new kernel during kexec)
#   - panic=10: the box reboots into Alt-F 10 s after a kernel crash
#
# Receive the messages on the PC before running this:
#   Linux:   nc -u -l -k 6666        (or: socat -u UDP-RECV:6666 -)
#   Windows: see README.txt
#
set -e

D=$(cd "$(dirname "$0")" && pwd)

for f in zImage kirkwood-dns320l.dtb rootfs.arm.sqmtd; do
	[ -s "$D/$f" ] || { echo "missing $D/$f"; exit 1; }
done

if ! grep -q "DNS-320L" /proc/device-tree/model 2>/dev/null && \
   ! grep -q "DNS-320L" /tmp/board 2>/dev/null; then
	echo "This does not look like a DNS-320L, aborting."
	exit 1
fi

BOXIP=$(ifconfig eth0 | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
BCAST=$(ifconfig eth0 | sed -n 's/.*Bcast:\([0-9.]*\).*/\1/p')
TARGET=${1:-$BCAST}
[ -n "$BOXIP" ] && [ -n "$TARGET" ] || { echo "cannot determine eth0 address"; exit 1; }

mkdir -p /boot
rm -f /boot/zImage /boot/rootfs.arm.* /boot/*.dtb /boot/cmdline
cp "$D/zImage" /boot/zImage
cp "$D/kirkwood-dns320l.dtb" /boot/kirkwood-dns320l.dtb
cp "$D/rootfs.arm.sqmtd" /boot/rootfs.arm.sqmtd
echo "console=ttyS0,115200 root=/dev/ram0 init=/init earlyprintk kexecmode panic=10 loglevel=8 netconsole=6666@${BOXIP}/eth0,6666@${TARGET}/" > /boot/cmdline

# Alt-F ships this line commented out in rcE; enable it for this one reboot
if grep -q '^#ifconfig eth0 down' /etc/init.d/rcE; then
	sed -i 's/^#ifconfig eth0 down/ifconfig eth0 down/' /etc/init.d/rcE
fi

echo
echo "Prepared in /boot:"
ls -l /boot
echo "cmdline: $(cat /boot/cmdline)"
echo
echo "Kernel messages will go to ${TARGET}:6666 (UDP)."
echo "Rebooting into ShareOS in 10 s – press Ctrl-C to cancel."
sleep 10
reboot
