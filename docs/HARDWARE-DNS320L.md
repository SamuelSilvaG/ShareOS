# DNS-320L rev A3 – hardware and boot findings

Collected while bringing up ShareOS phase 1 (2026-10-16).

## Network

- Alt-F (kernel 4.14, generic PHY driver) links at **1000 Mbit/s full duplex**
  on a rev A3 board. The Marvell PHY driver is therefore only built as a module.

## Flash (`/proc/mtd` under Alt-F)

| mtd | size | name |
|---|---|---|
| mtd0 | 0x00100000 | u-boot |
| mtd1 | 0x00500000 | uImage |
| mtd2 | 0x00500000 | ramdisk |
| mtd3 | 0x06400000 | image |
| mtd4 | 0x00a00000 | mini firmware |
| mtd5 | 0x00500000 | config |
| mtd6 | 0x00200000 | my-dlink |

Reading mtd0 with `nanddump` reports uncorrectable ECC errors on the first two
pages (0x0, 0x800): those pages use the boot ROM ECC layout, not the one the
Linux NAND driver expects. The rest of the dump is valid.

## Stock U-Boot

- `U-Boot 1.1.4 (Aug 22 2012) Marvell version: 3.6.0.DNS-320L.01`, linked at
  0x600000 (NAND image offset 0x200).
- **No saved environment** in mtd0 (no CRC-valid block) – the compiled-in
  defaults are used:
  - `bootcmd=nand read.e 0xa00000 0x100000 0x300000;nand read.e 0xf00000 0x600000 0x300000;bootm 0xa00000 0xf00000`
    → only 3 MB of the uImage and ramdisk partitions are read (hard size limit)
  - `bootargs=root=/dev/ram console=ttyS0,115200 :::DB88FXX81:egiga0:none`
  - `bootdelay=1`, `ipaddr=2.66.66.201`, `serverip=2.66.66.32`, `rcvrip=169.254.100.100`
- Commands present: `usb`, `fatload`, `ext2load`, `usbboot`, `rcvr`.
- `rcvr` (Marvell recovery): loads `/flashware.img` or `/multiware.img` from a
  USB stick (FAT, then ext2 partitions 0/1); if not found, does a DHCP/TFTP
  "distress beacon" recovery; then boots the image from RAM (no flashing).
- Auto-recovery at power-on is wired to a board GPIO of class 17. The DNS-320L
  runs as board "DB-88F6702A-BP" (board id 14, default when unset), whose GPIO
  table has **no class-17 entry** → `rcvr` can only be started from the serial
  console, there is no button-triggered recovery.

## kexec

- Alt-F greys out "TryIt" on Kirkwood boxes.
- Manual kexec from Alt-F into the ShareOS kernel hung before netconsole came
  up (no UDP packets, LEDs unchanged).
- kexec of Alt-F's **own** flashed kernel (`touch /boot/.kexec; reboot`) also
  hung → kexec with the Alt-F 4.14 kernel does not work on this box at all.

## Consequence

There is no safe way to run an untested kernel without a serial console.
The JP1 serial header is not populated (3.3 V TTL, 115200 8N1, GND/TX/RX);
a pin header pressed into the holes works without soldering for diagnostics.
With the console, ShareOS can be started from RAM via `rcvr`/TFTP or
`tftpboot` + `bootm` without touching the flash.
