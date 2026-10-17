# Testing and installing ShareOS (DNS-320L)

*Deutsche Version: [TESTEN.md](TESTEN.md)*

As of 2026-10-17, ShareOS is in its **test phase**. Installing it on a box that
runs Alt-F currently needs the **serial console** (header JP1, no soldering, see
[HARDWARE-DNS320L.md](HARDWARE-DNS320L.md)). Once ShareOS is installed, updates
go through the web interface.

Every step can be undone: ShareOS first runs from RAM only, then the system
goes into flash, and the kernel is written last. The Alt-F partitions are
backed up before anything is overwritten.

## What you need

- the update bundle `ShareOS-<version>-DNS-320L-rev-Ax.sysupgrade.tar` from a
  GitHub release
- a USB-TTL adapter (3.3 V) on JP1: pin 4 = box TX, 3 = GND, 1 = box RX; leave
  pin 2 (3.3 V) unconnected. Settings: 115200 8N1
- a PC with a TFTP server, for example `dnsmasq`

## 1. Prepare the PC

```sh
sudo mkdir -p /srv/tftp && sudo rm -f /srv/tftp/*
sudo tar xf ShareOS-*.sysupgrade.tar -C /srv/tftp
cd /srv/tftp && sha256sum -c SHA256SUMS
sudo dnsmasq --no-daemon --port=0 --enable-tftp --tftp-root=/srv/tftp --tftp-single-port
```
The PC's firewall must let UDP port 69 through, for example
`sudo ufw allow from <net>/24 to any port 69 proto udp`.

## 2. Boot from RAM (writes nothing)

Power the box on and immediately type **space, 1, space, 1 …** until
`Marvell>>` appears. Then:
```
setenv ipaddr <free ip>
setenv serverip <pc ip>
setenv netmask 255.255.255.0
setenv bootargs shareos.netroot=<pc ip>
tftpboot 0xa00000 uImage
tftpboot 0xf00000 urootfs
bootm 0xa00000 0xf00000
```
Never type `saveenv`. Log in as `root` / `shareos`. Run `shareos-check` to
check the hardware.

## 3. Write the system to flash

> The `.bin` of a release only contains the kernel and the boot system. Flashed
> from the Alt-F or D-Link firmware page, the box then starts in rescue mode
> until the system (step below) is installed. An install page for this is
> planned.

On the box, still in the network boot from step 2:
```sh
shareos-install-ubi tftp://<pc ip>/rootfs.squashfs --yes
shareos-flash-boot tftp://<pc ip> --yes
```
- The first command writes the system to the `image` partition. This
  replaces Alt-F's extra packages; Alt-F itself still boots.
- The second command writes the kernel and initramfs. It first backs up
  Alt-F's partitions to `/root/boot-backup`. Copy that backup to your PC:
  `scp -O -r root@<ip>:/root/boot-backup .`

Then `reboot`: the box starts ShareOS on its own.

## 4. Web interface

Open `http://<ip>` and log in as `root` / `shareos`. Change the password
right away under **System → General**.

## 5. Updates

- **From the web interface:** System → Firmware → *Check now*. For test
  versions, choose the **Beta** channel.
- **By hand**, with a bundle on the box:
  ```sh
  cd /tmp && mkdir u && tar xf ShareOS-*.sysupgrade.tar -C u
  shareos-flash-boot /tmp/u --yes
  mkdir -p /overlay/upgrade && cp /tmp/u/rootfs.squashfs /overlay/upgrade/
  cd /overlay/upgrade && sha256sum rootfs.squashfs > rootfs.squashfs.sha256 && echo <version> > version
  sync && reboot
  ```
  During boot the console shows `upgrade: installing system … done`.

Settings and installed packages are kept across updates.

**Versions up to 0.1.0-beta.1:** curl does not find the CA certificates there,
and the check against GitHub reports "certificate is not correctly signed".
Run this once on the box, then the update works (not needed from 0.1.0-beta.2):
```sh
echo 'cacert = /etc/ssl/certs/ca-certificates.crt' > /root/.curlrc
```

## 6. Network

A static IP can be set under **System → Network**. The change takes effect at
once; the box then waits 2 minutes for a confirmation from the new address.
The web interface opens the new address itself and confirms. Without a
confirmation (typo, wrong network) the box restores the old settings. Last
resort: factory reset (DHCP) from the serial console with
`shareos-factory-reset --yes`.

## 7. Shares and users

Create accounts under **Shares → Users** (role, personal folder, storage
limit), share folders under **Shares → Shares** and set permissions per user or
group. Windows: `\\<box>\<share>`, macOS/Linux: `smb://<box>/<share>`. Users
with web access see "My ShareOS" after login (own storage, shares, password,
Paperless, cloud).

## 8. Paperless-ngx

1. In Paperless: Profile → create an **API token**.
2. In ShareOS under **Paperless** enter the address (e.g. `http://192.168.1.20:8000`) and save.
3. **New inbox**: personal (folder `Paperless` in a user's personal folder) or shared (folder of a share, e.g. for the scanner), enter the token, **Test connection**.
4. Put a PDF into the inbox folder. Within 2 minutes (or at once with **Send now**) the log shows "processing", then "accepted", and the document is in Paperless.

Files Paperless rejects (e.g. duplicates) are moved to `.paperless/failed` in
the inbox folder. If Paperless cannot be reached, the file stays and is sent on
the next run.

## 9. Cloud sync

1. **Cloud → install rclone** (downloads rclone from GitHub, needs an apps area).
2. **Add account**: Nextcloud/WebDAV, S3 or SFTP directly; Google Drive, OneDrive, Dropbox: run `rclone config` on a PC and paste the finished section from `rclone.conf`. **Test** shows whether the login works.
3. **New job**: folder on the NAS, account, folder in the cloud, direction (upload is the safe choice, mirroring deletes on the target side), schedule. **Start now** and look at the **log**.

Users may create their own accounts and jobs when "May create own cloud sync
jobs" is set in their account (needs a personal folder). Their jobs run with
their permissions.

## 10. App and widgets

- **As an app:** Chrome and Edge offer "Install app" only over HTTPS with a trusted certificate (e.g. Let's Encrypt, install it under System → Network). Over http:// "Add to home screen" works (bookmark icon). Long-pressing the app icon shows the shortcuts.
- **Widgets:** enable under **System → General → Status for widgets** and copy the address. It returns JSON, e.g.:
  ```sh
  curl "http://<box>/cgi-bin/status?token=<token>"
  ```
  In KWGT (Android) values can be shown with `$wg("<address>", json, ".volumes[0].used_pct")$`. **New key** makes the old address invalid.

## If something goes wrong

| Sign | Meaning / fix |
|---|---|
| The orange USB LED blinks | Rescue mode: the reason and the SSH address are on the console. `shareos-install-ubi` is available there. |
| U-Boot reports a bad image header | U-Boot boots the D-Link rescue system on its own. Flash Alt-F from its web page. |
| The kernel hangs | Boot over TFTP as in step 2 and write the backup back: `flash_erase /dev/mtd1 0 0; nandwrite -p /dev/mtd1 uImage.bin` (mtd2 with `ramdisk.bin`) |
| Back to Alt-F completely | Write the backup back (row above), then re-flash Alt-F's extra packages from Alt-F |

ShareOS never touches U-Boot, the MAC address or the D-Link rescue system.
