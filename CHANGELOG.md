# Changelog

Changes per release (newest first). The section of a version is added to its
GitHub release automatically when the release is built. Test versions are
pre-releases for test devices only.

## 0.1.0-beta.8

- **File system per volume:** ext4 (recommended), Btrfs, exFAT or NTFS in the storage wizard and when formatting a disk; the interface says what each choice means (permissions, storage limit, personal folders, apps).
- **USB sticks and disks:** mounted automatically at `/mnt/usb-<name>` when plugged in (FAT32, exFAT, NTFS, ext4, Btrfs), visible in the file browser for admins, **Safely remove** button, **Format** with exFAT, FAT32, NTFS or ext4. The disks in the bays are never touched by this.
- Tools on board: mkfs for Btrfs, exFAT, FAT and NTFS.
- **System → Time:** time zone, NTP on/off with own time servers (e.g. the router), *sync now*, set the clock by hand (or take the time of the browser); the battery clock of the box is set too.
- Page addresses in English (`#/storage`, `#/shares/users`, `#/system/time` …); old German links and app shortcuts are redirected.
- **10 languages:** English, German, Chinese, Hindi, Spanish, French, Arabic (right to left), Bengali, Portuguese and Russian. Translations other than English/German by AI – corrections welcome.
- **Scheduled tasks for apps** (permission `cron`): an app can declare tasks in its `app.json` (script from the package, schedule, time limit). They run as the app's own restricted user (`app-<id>`), only in its data folder, at most every 5 minutes and up to 5 per app. The install dialog lists the permissions; *Apps → Tasks* changes the schedule, switches tasks on/off, runs them now and shows the last log.
- Fix: an own HTTPS certificate (e.g. a wildcard certificate of an own CA) was always refused with "certificate and key do not match" when uploaded in the web interface – the check failed because of file permissions, not because of the certificate.

## 0.1.0-beta.7

- **Install without the serial console:** flash the ShareOS `.bin` from the Alt-F or D-Link firmware page. On the first start ShareOS installs its system by itself – from a USB stick with the `.sysupgrade.tar` (FAT32/exFAT/ext4) or from GitHub (checksum verified). Not yet tried on real hardware.
- **Back to Alt-F from the web interface:** System → Firmware → *Install firmware file* writes another D-Link `.bin` (e.g. Alt-F); the file is checked (format, checksums, device, 3 MB limit) and read back after writing.
- Tests for both paths (emulator and host).
- Fix: the APPS area logged admins out ("session expired") – its functions were missing from the access rules. A new CI check makes sure every function is covered.
- Fix: the system log used UTC instead of the time zone set on the box.
- Messages such as "Last update: installed" or a failed disk setup can be closed with an **x**; the box forgets them.
- Disk setup: a disk still held by a RAID or another firmware is named in the message; erasing retries once and reports the reason.

## 0.1.0-beta.6

- **APPS area with a store** for ShareOS apps from [ShareOS-Apps](https://github.com/UniqueDroid/ShareOS-Apps): install and update with SHA-256 check, upload own packages (`.sapp`), more catalogs as sources, visibility per user/group, apps in "My ShareOS". First app: Webpad.
- Web apps run on their own port (8081 / 8444) – another origin than the admin interface.
- Firmware update: "Restart now" appears only after the installation has finished; the progress bar ends at 100 %.
- Settings backup also covers Paperless, cloud and apps.
- Docs: photos of the board and the serial console (JP1).

## 0.1.0-beta.5

- File browser: admins for all drives, users for their personal folder (enabled per user); upload/download with progress, drag and drop, large files.
- Own look (light/dark, accent) per user.
- Reachable as `<name>.local` (mDNS); fallback address `192.168.0.32` when no DHCP server answers.
- The box checks for new firmware every 6 hours by itself.
- The self-signed certificate follows hostname and IP address.
- Forms: fields aligned, file pickers look like buttons; login prompt `user@shareos`.

## 0.1.0-beta.4

- Paperless-ngx: inbox folders per user or shared (e.g. for a scanner).
- Cloud sync with rclone (Nextcloud/WebDAV, S3, SFTP, Google Drive …) for the device and per user.
- Installable as an app (PWA) and a status address for widget apps.

## 0.1.0-beta.3

- Shares (ksmbd SMB, NFS) with permissions per user and group, storage limit per user.
- Users and groups, "My ShareOS" for users, import of Alt-F users with passwords.
- Settings backup and restore (JSON, optionally AES-256).

## 0.1.0-beta.2

- Menu after the concept, network page with automatic rollback, services with autostart, tile/table views, light/dark/system look with accent colours.
- Progress for download, check and installation of updates.

## 0.1.0-beta.1

- First test release: runs from flash, storage assistant, web interface, online update from GitHub releases.
