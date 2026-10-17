# ShareOS flash layout and boot flow (DNS-320L)

```
mtd0 u-boot         1 MB   stock U-Boot – never touched
mtd1 uImage         5 MB   kernel + DTB (U-Boot reads 3 MB)          ← .bin part 1
mtd2 ramdisk        5 MB   ShareOS initramfs (U-Boot reads 3 MB)     ← .bin part 2
mtd3 image        100 MB   UBI:  rootfs       squashfs, read-only system
                                 rootfs_data  UBIFS, rest of the space (overlay)
mtd4 mini firmware 10 MB   D-Link rescue system + MAC address – never touched
mtd5 config         5 MB   left alone (Alt-F settings stay, easy way back)
mtd6 my-dlink       2 MB   never touched
```

## Boot flow

1. U-Boot loads uImage + initramfs (`bootcmd`, unchanged stock U-Boot).
2. Kernel 6.18 (UBI, ubiblock, UBIFS, squashfs, overlayfs built in) runs `/init`
   from the initramfs (`board/dlink/dns320l/initramfs/init`):
   - **flash** (default): if mtd3 starts with `UBI#`, attach it, expose volume
     `rootfs` via ubiblock, mount squashfs, mount `ubi0:rootfs_data` (UBIFS
     formats itself on first mount), overlay both on `/`, `switch_root`.
     The read-only system is visible at `/rom`, the writable layer at `/overlay`.
   - **`shareos.netroot=<tftp server>`**: fetch `rootfs.squashfs` via TFTP into
     RAM, overlay in tmpfs – **nothing is written to flash**.
   - **`shareos.rescue`** or any failure: stay in the initramfs – DHCP, SSH
     (dropbear), serial login, flash tools, `shareos-install-ubi`. Orange USB
     LED blinks.
3. The squashfs root runs BusyBox init and the normal ShareOS services.

The initramfs never attaches mtd3 unless it already carries UBI, so foreign
data (Alt-F's extra-package squashfs) is never touched implicitly.

## Installing / updating the system volume

`shareos-install-ubi <rootfs.squashfs | tftp://host/file | http://…> --yes`
(in the initramfs and in the full system; refuses while the flash system is
mounted):

- first install: `ubiformat` mtd3 (keeps erase counters), volume `rootfs`
  (48 MiB) + `rootfs_data` (rest)
- `--keep-data`: replace only `rootfs`, settings and packages stay

Factory reset = empty `rootfs_data` (UI function to follow).

## Netboot (development, no flashing)

The build produces `shareos-netboot-<version>.tar` (uImage, urootfs,
rootfs.squashfs). On the PC: unpack into the TFTP root and run
`dnsmasq --no-daemon --port=0 --enable-tftp --tftp-root=/srv/tftp --tftp-single-port`.
In U-Boot (stop with `<space>1`):

```
setenv ipaddr <free ip>; setenv serverip <pc ip>; setenv netmask 255.255.255.0
setenv bootargs root=/dev/ram console=ttyS0,115200 shareos.netroot=<pc ip>
tftpboot 0xa00000 uImage
tftpboot 0xf00000 urootfs
bootm 0xa00000 0xf00000
```
(no `saveenv` – U-Boot keeps its stock settings)

## Sizes (build cad09bb)

| part | size | limit |
|---|---|---|
| uImage (kernel + DTB) | 2.38 MB | 3 MB |
| initramfs | 0.92 MB | 3 MB |
| rootfs.squashfs | 5.0 MB | 48 MB volume |
