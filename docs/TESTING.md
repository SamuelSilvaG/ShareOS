# Testing and installing ShareOS (DNS-320L)

*Deutsche Version: [TESTEN.md](TESTEN.md)*

As of 2026-10-18, ShareOS is in its **test phase**. There are two ways to
install it:

- **Way A – from the Alt-F or D-Link firmware page** (no serial console, from
  0.1.0-beta.7 on). Not yet tried on real hardware: for the first time, best
  keep the serial console connected as a safety net.
- **Way B – over the serial console** (header JP1, no soldering, see
  [HARDWARE-DNS320L.md](HARDWARE-DNS320L.md)): tested, steps 1–3 below.

Once ShareOS is installed, updates go through the web interface. Going back to
Alt-F works from the web interface too (see [Back to Alt-F](#back-to-alt-f)).

## Way A: from the Alt-F or D-Link firmware page

From the GitHub release you need:

- `ShareOS-<version>-DNS-320L-rev-Ax.bin` (kernel and boot system, about 3.3 MB)
- recommended: `ShareOS-<version>-DNS-320L-rev-Ax.sysupgrade.tar` on a USB
  stick (FAT32, exFAT or ext4; top folder or folder `shareos`). Without a
  stick the box downloads the bundle from GitHub itself – the network cable
  must be plugged in and the router must hand out an address (DHCP).

1. Plug the USB stick with the bundle into the box (if you have one).
2. In the Alt-F (or D-Link) web interface, select the ShareOS `.bin` on the
   firmware page and flash it. Alt-F only writes the kernel and boot system.
3. The box restarts. ShareOS notices that there is no system in flash yet and
   installs it: from the USB stick, otherwise from GitHub (the checksum is
   verified). The **orange USB LED blinks fast**; this takes a few minutes.
   Alt-F's extra packages in flash are replaced.
4. The box then restarts on its own – now with ShareOS. Continue with
   [4. Web interface](#4-web-interface).

If the installation fails (no stick, no network, damaged bundle), the box
stays in **rescue mode** (orange USB LED blinks slowly). The reason is on the
serial console and, over SSH (`ssh root@<ip>`, password `shareos`), in
`/tmp/firstinstall.err`; the log is `/tmp/firstinstall.log`. Fix: copy the
bundle to a USB stick, plug it in, switch the box off and on again.

## Way B: over the serial console

### What you need

- the update bundle `ShareOS-<version>-DNS-320L-rev-Ax.sysupgrade.tar` from a
  GitHub release
- a USB-TTL adapter (3.3 V) on JP1: pin 4 = box TX, 3 = GND, 1 = box RX; leave
  pin 2 (3.3 V) unconnected. Settings: 115200 8N1
- a PC with a TFTP server, for example `dnsmasq`

### Connecting the serial console (no soldering)

JP1 sits next to the USB port and is not populated. It is enough to push the
adapter's wires (Dupont cables) through the holes and secure them with a little
hot glue. Pin 1 is the square pad (arrow on the board); there is a gap between
pin 1 and pin 2.

| JP1 pinout | What it looks like connected |
|---|---|
| ![JP1 pinout](images/hw-jp1.jpg) | ![JP1 with wires](images/hw-jp1-kabel.jpg) |

| Setup with a USB-serial adapter | Board overview |
|---|---|
| ![Setup](images/hw-seriell-aufbau.jpg) | ![Board](images/hw-platine.jpg) |

On the PC: `screen /dev/ttyUSB0 115200` (or PuTTY/minicom). The adapter must be
set to **3.3 V** – 5 V can damage the box. TX and RX are crossed: the adapter's
TXD goes to pin 1 (box RX), RXD to pin 4.

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

Open `http://shareos.local` (or `http://shareos.fritz.box`, `http://<ip>`) and
log in as `root` / `shareos`. Change the password right away under
**System → General**.

- The box gets its address by **DHCP** from the router and registers its name there.
- Via **mDNS** it also answers as `<name>.local` (Windows 10/11, macOS, iOS, Android, Linux).
- If no DHCP server answers (box connected straight to a PC), it takes the **fallback address `192.168.0.32`** after about 15 s. Set the PC to e.g. `192.168.0.10/24`. As soon as a DHCP server answers, the box switches by itself.
- The self-signed HTTPS certificate names the hostname, `<name>.local` and the current IP. After a change it is reissued (the browser asks once more).

## 5. Updates

- **Automatically:** the box looks at GitHub every 6 hours. A new release shows up at the top as **UPDATE … available** once GitHub has built the update bundle (about 45 minutes after publishing).
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

## 11. File browser and own look

- **Admins:** Shares → **Files** shows every mounted drive: create folders, upload (also by dragging), download, rename, move, copy, delete.
- **Users:** enable "File browser for the personal folder" in the user account. "My ShareOS" then has a **Files** tab, only for the own folder and with the user's own rights.
- **Look:** users with web access set light/dark and the accent colour for themselves under **Appearance**. "Same as for everyone" goes back to the admin's choice.
- Test idea: upload a large file (e.g. 1 GB) and download it again. It must not stop after 60 s.

## 12. Apps (store)

- **APPS → Store → Refresh now** loads the catalog from the [ShareOS-Apps](https://github.com/UniqueDroid/ShareOS-Apps) repository. **Install** next to **Webpad**: the box downloads the package, checks its SHA-256 and installs it.
- **APPS → Installed → Open ↗** starts the app in a new tab on port **8081** (8444 with HTTPS) – deliberately another address than the admin interface.
- **Users** decides who sees the app in "My ShareOS" (everyone, single users, groups).
- **Own app:** upload a `.sapp` file under Store → *Install package* (built with `tools/build.py` from the app repository). It is marked "own / not verified".
- **More sources** (own catalogs) under APPS → Sources.
- **Scheduled tasks** (from beta.7, for apps with the permission `cron`): the install dialog lists the permissions. **APPS → Installed → Tasks** shows schedule, on/off and the last run; *Run now*, then *Log* shows the output. A changed schedule stays after an app update. Check with `crontab -l` (line `shareos-apps run-job`) and `ps` (the job runs as user `app-<id>`).

## 12a. Update without internet

- Download `ShareOS-<version>-DNS-320L-rev-Ax.sysupgrade.tar` and its `.sha256` from a release on the PC.
- **System → Firmware → Install firmware file**: choose the `.tar` as *File* and the `.sha256` as *Checksum*, **Upload & check**. After about half a minute the update panel shows "<version> install" with "Uploaded file – verified …".
- **Install**, then **Restart now** – the same as an update from GitHub.
- Wrong `.sha256`, a file for another device or a damaged file are refused with a message.

## 13. File systems and USB drives

- **Storage → Wizard**: in the "Name" step every volume gets a choice of **ext4** (recommended, everything), **Btrfs** (no storage limit per user), **exFAT** and **NTFS** (also readable on Windows/macOS; no permissions per user, no storage limit, no personal folders, no apps). The summary shows the chosen file system. "Erase & format" on a disk has the same field.
- **Plug in a USB stick**: it shows up under Storage → Disks as "USB · sdX" and is mounted at `/mnt/usb-<name>` after a few seconds (FAT32, exFAT, NTFS, ext4, Btrfs). Admins see it in the file browser.
- **Safely remove** writes everything, unmounts and powers the stick down, then shows "sdX can be unplugged now". If a stick is pulled without it, ShareOS cleans up the mount point.
- **Format** (on a USB drive): choose a name and a file system – **exFAT** (recommended), **FAT32**, **NTFS** or **ext4**. The stick gets one partition (MBR) so every computer, camera and TV can read it.
- The disks in the bays are never mounted automatically; the USB functions do not touch them.

- **Two disks:** besides "Mirror (RAID 1)" and "two separate volumes" the wizard offers **RAID 0** and **JBOD**; the summary shows the size (RAID 0: twice the smaller disk, JBOD: both together). `cat /proc/mdstat` shows `raid0` or `linear`.
- File systems **ext3**, **ext2** and **FAT32** can be chosen for disks too (FAT32: files up to 4 GB).
- **Repair a mirror:** with a disk of a mirror missing (card: "one disk missing (U_)") and a disk in the free bay, *Repair mirror* erases that disk and adds it; the card then shows "Recovery … %".

## 14. Time and languages

- **System → Time:** the box's clock runs live in its time zone. Change the time zone, switch NTP off and on, enter own time servers (e.g. `fritz.box`), *Sync now*. With NTP off the clock can be set by hand or taken from the browser. Logs then show the local time.
- **System → Appearance → Language:** 10 languages (English, German, Chinese, Hindi, Spanish, French, Arabic, Bengali, Portuguese, Russian). Arabic switches the page to right to left. Translations other than German/English are machine-made – please report mistakes.

## 14a. Open files in apps

- Install **Webpad 1.1** (store). In the file browser a `.txt` file shows **Webpad ↗**; click it (or the file name): Webpad opens in its own window with the file.
- Change something, **Ctrl+S**: the message says "saved"; the file browser shows the new size and time. Owner and rights of the file stay.
- Look: switch light/dark or the accent colour in ShareOS – an open app follows.
- Users with a personal folder can do the same with their files.

## 15. Buttons

- **Reset button** (pin hole at the back), hold and let go:
  - shorter than 5 s: nothing;
  - **5–10 s** (orange USB LED blinks slowly): **access reset** – network back to DHCP (fallback `192.168.0.32`), root password `shareos`, web interface over http again with a new self-signed certificate; users, shares, apps and data stay; the box restarts;
  - 10–15 s (LED off): cancelled;
  - **15 s or longer** (LED blinks fast): **factory reset** – all settings and installed packages are removed, the data on the disks stays.
- **USB button** (front): safely removes all USB drives.
- What happened is in the system log (`shareos-buttons`).

## Back to Alt-F

1. Have the Alt-F `.bin` for the DNS-320L ready (e.g. `Alt-F-1.0-DNS-320L-rev-A.bin`).
2. In ShareOS, upload it under **System → Firmware → Install firmware file**.
   ShareOS checks it (D-Link format, checksums, device, size) and shows what
   is inside.
3. **Install** – kernel and boot system are written and read back. Then
   **Reboot**: Alt-F starts.
4. Alt-F then runs without its extra packages. Flash the same `.bin` once
   more from Alt-F's firmware page to get them back.

Back to ShareOS: flash the ShareOS `.bin` from Alt-F. As long as Alt-F has not
overwritten the `image` partition (step 4 skipped), the ShareOS system and
settings are still there; otherwise ShareOS installs itself again as in way A.
The D-Link firmware is best installed from Alt-F.

## If something goes wrong

| Sign | Meaning / fix |
|---|---|
| The orange USB LED blinks | Rescue mode: the reason and the SSH address are on the console. `shareos-install-ubi` is available there. |
| U-Boot reports a bad image header | U-Boot boots the D-Link rescue system on its own. Flash Alt-F from its web page. |
| The kernel hangs | Boot over TFTP as in step 2 and write the backup back: `flash_erase /dev/mtd1 0 0; nandwrite -p /dev/mtd1 uImage.bin` (mtd2 with `ramdisk.bin`) |
| Back to Alt-F completely | Easiest from the web interface (see [Back to Alt-F](#back-to-alt-f)). Without it: write the backup back (row above), then re-flash Alt-F's extra packages from Alt-F |

ShareOS never touches U-Boot, the MAC address or the D-Link rescue system.
