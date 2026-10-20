# Supported devices and testers

*Deutsche Fassung: [GERAETE.md](GERAETE.md)*

ShareOS was developed on the **D-Link DNS-320L rev A**. From 0.2.0-beta.3 the
same system is built for the related Kirkwood boxes as well. They share the
processor family, the flash layout and the stock U-Boot; what differs (fan,
temperature sensor, buttons, LEDs, power-off) is described per model in
[`/usr/lib/shareos/board.sh`](../board/dlink/dns320l/rootfs-overlay/usr/lib/shareos/board.sh).

| Model | Release files | RAM | Status |
|---|---|---|---|
| DNS-320L rev A (A1–A3) | `ShareOS-<ver>-DNS-320L-rev-Ax.*` | 256 MB | **tested** |
| DNS-320 rev B | `ShareOS-<ver>-DNS-320-rev-Bx.*` | 128 MB | built, **testers wanted** |
| DNS-325 rev A | `ShareOS-<ver>-DNS-325-rev-Ax.*` | 256 MB | built, **testers wanted** |
| DNS-320 rev A | `ShareOS-<ver>-DNS-320-rev-Ax.*` | 128 MB | built, **testers wanted** |
| DNR-322L | – | 128 MB | planned |
| DNS-327L | – | 512 MB | planned (own kernel and flash layout) |

Not possible: DNS-323, DNS-321, DNS-343 (64 MB RAM, 8 MB flash).

## How the models differ

| | DNS-320L / 320 rev B | DNS-325 | DNS-320 rev A |
|---|---|---|---|
| Fan, temperature | Weltrend MCU on ttyS1 (`dns320l-daemon`) | `gpio-fan`, `lm75` sensor (kernel) | `gpio-fan`; temperature asked from the MCU on ttyS1 |
| Power button | GPIO 29, polled | gpio-keys | gpio-keys |
| Power-off, power-on after a power cut | MCU | `gpio-poweroff`, GPIO 37 | `gpio-poweroff`, GPIO 37 |
| Clock (RTC) | MCU | kernel (`/dev/rtc0`) | kernel |
| LEDs | `dns320l:*` | `dns325:*` | `dns320:*` |
| D-Link signature | `DNS320L` / `DNS320B` | `DNS-325` | `DNS323D1` |

One kernel serves all four: post-image appends the model's device tree to the
kernel (the stock U-Boot passes none) and writes a `.bin` with the model's
signature. Initramfs and system are the same; the box finds its model in the
device tree at boot (`shareos-boardinfo`).

## For testers

**You need:** one of the boxes above with Alt-F or the D-Link firmware, a
USB stick (FAT32/exFAT/ext4), a network with DHCP. No soldering, no serial
console.

1. Download from the [latest release](https://github.com/UniqueDroid/ShareOS/releases)
   the two files with **your model's name**:
   `ShareOS-<ver>-<model>.bin` and `ShareOS-<ver>-<model>.sysupgrade.tar`.
2. Copy the `.sysupgrade.tar` to the USB stick and plug it in.
3. Flash the `.bin` on the firmware page of Alt-F or the D-Link interface
   (the box refuses files for another model).
4. The box restarts, installs the system from the stick (USB LED blinks fast,
   a few minutes) and restarts again into ShareOS: `http://<box-IP>/`,
   user **root**, password **shareos**.
5. Please check and report (GitHub issue, title "Test <model>"):
   - System → About: device and firmware name right?
   - Overview: temperature shown? Fan audible at the presets of System →
     Power & reset (quiet / balanced / cool)?
   - Power button: the box shuts down; it switches off completely?
   - Reset button 5–10 s: access reset (USB LED blinks slowly while held)
   - USB button: USB drives are removed safely
   - LEDs: status and disk LEDs (System → Power & reset)
   - After a power cut: does the box start again by itself?
   - System → Time: correct after a restart without network?
   - Storage: create a volume, share, copy files from a computer
   - Free memory after start (System → Terminal: `free`), above all on the
     128 MB boxes
   - The hardware report: System → Terminal → `shareos-check`, attach
     `/tmp/shareos-check.txt`

**The way back** is always there: System → Firmware → *Install firmware
file* with the Alt-F `.bin` (see [SWITCHING.md](SWITCHING.md)). If the box
does not start into ShareOS, U-Boot starts the D-Link rescue system ("mini
firmware"), from which Alt-F can be flashed. The data on the disks is never
touched.

## Adding a model

1. Device tree: in the kernel (`BR2_LINUX_KERNEL_INTREE_DTS_NAME`) or in
   `board/dlink/dns320l/dts/` (`BR2_LINUX_KERNEL_CUSTOM_DTS_PATH`).
2. A line in `MODELS` of `board/dlink/dns320l/post-image.sh` (firmware name,
   device tree, D-Link signature from `legacy/alt-f/mkfw.sh`).
3. A case in `board_detect` of `board.sh` (model text, LEDs, control,
   buttons) and in `tests/test-boards.sh`.
