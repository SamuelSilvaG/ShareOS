# Changelog

Changes per release (newest first). The section of a version is added to its
GitHub release automatically when the release is built. Test versions are
pre-releases for test devices only.

## 0.1.0-beta.10

- **Apps open under the box's name:** links to apps (store, file browser, *My ShareOS*) used the address the interface was opened with – an IP address gave a certificate warning on port 8444 although a certificate for the name was installed. Apps now open under the name the installed certificate is valid for (a wildcard certificate `*.skynet.lan` gives `<hostname>.skynet.lan`) or under a name set by hand: System → Network → *Box name for links*. Opened by IP, the HTTPS panel links to the name.
- **App icons** of installed apps are shown again: they come with the app list instead of being loaded from the apps web server (other port, and a browser does not ask about a certificate for images).
- The apps web server (port 8081/8444) is now watched like the interface: it comes back on its own after a crash and after every certificate or network change, always with the current certificate.

## 0.1.0-beta.9

- **Update without internet:** System → Firmware → *Install firmware file* also takes the `.sysupgrade.tar` of a release (best with its `.sha256`). It is checked like an update from GitHub (checksums of all parts, made for this box, sizes) and then installed with the usual button – for boxes without internet or with GitHub blocked. Older and newer versions can be installed this way.
- **Reset button** (back): held 5–10 s = access reset (network back to DHCP with fallback 192.168.0.32, root password `shareos`, web interface over http with a new self-signed certificate; everything else stays), 15 s or longer = factory reset (settings and packages; the data on the disks stays), 10–15 s = cancel. The orange USB LED shows the zone while holding. Before, the button did nothing.
- **USB button** (front): safely removes all USB drives.
- **Open files in apps:** the file browser shows "<App> ↗" next to files an installed app can open (e.g. Webpad for text files); a click on the name opens the file there, in a window of the app's size. The app gets a ticket for exactly this file and the user's rights, saving writes back (owner and rights of the file stay).
- **App platform:** apps declare `window` (size) and `opens` (file types, view/edit) in `app.json`; the apps web server serves `/_shareos/theme.css` (look of ShareOS, light/dark, accent colour, title/menu/status bars like Notepad++, scroll bars) and `/_shareos/app.js` (menu bar, opened file, messages between apps). Apps get the user's look and follow changes.
- New permission **`embed`**: apps that only have settings are shown inside the ShareOS interface instead of their own window.
- **Storage:** the wizard also offers **RAID 0** (both disks as one fast volume) and **JBOD** (both disks one after the other, full space, also for different sizes) besides the mirror; both without redundancy, the wizard says so. File systems **ext3**, **ext2** and **FAT32** for the disks too.
- **Repair a mirror:** when one disk of a mirror is missing or failed, put a new disk into the free bay and click *Repair mirror* – the disk is added and the data copied in the background (progress in the volume card).
- **Messages (System → Messages):** the box checks RAID, volumes (mounted, how full), temperature, SMART values and updates every 10 minutes; failed cloud jobs, app tasks and storage jobs report at once. Messages are listed in the interface (header chip "1 MESSAGE"), can be sent by **e-mail** (SMTP with STARTTLS/SSL) and as **push** to the phone (**ntfy**, **Gotify** or a JSON webhook), each with its own minimum level; repeated messages are counted and sent again at most once a day. Limits for temperature and full volumes are adjustable; *Test message* checks the setup.
- Fix: after installing a certificate the apps web server (port 8081/8444) did not come back until the next restart.

## 0.1.0-beta.8

- Fix: an own HTTPS certificate (e.g. a wildcard certificate of an own CA) was always refused with "certificate and key do not match" when uploaded in the web interface – the check failed because of file permissions, not because of the certificate.
- Main menu: labels are centred vertically in the buttons (before they sat slightly too high).
- Fix: apps with a minimum ShareOS version (e.g. Webpad, "0.1.0") were refused on the betas with "needs a newer ShareOS". A minimum without beta is now met by the betas of that version.
- Fix: versions are compared number by number also in the beta part, so `beta.10` counts as newer than `beta.9` (firmware updates and apps).

## 0.1.0-beta.7

- **Install without the serial console:** flash the ShareOS `.bin` from the Alt-F or D-Link firmware page. On the first start ShareOS installs its system by itself – from a USB stick with the `.sysupgrade.tar` (FAT32/exFAT/ext4) or from GitHub (checksum verified). Not yet tried on real hardware.
- **Back to Alt-F from the web interface:** System → Firmware → *Install firmware file* writes another D-Link `.bin` (e.g. Alt-F); the file is checked (format, checksums, device, 3 MB limit) and read back after writing.
- Tests for both paths (emulator and host).
- Fix: the APPS area logged admins out ("session expired") – its functions were missing from the access rules. A new CI check makes sure every function is covered.
- Fix: the system log used UTC instead of the time zone set on the box.
- Messages such as "Last update: installed" or a failed disk setup can be closed with an **x**; the box forgets them.
- Disk setup: a disk still held by a RAID or another firmware is named in the message; erasing retries once and reports the reason.
- **File system per volume:** ext4 (recommended), Btrfs, exFAT or NTFS in the storage wizard and when formatting a disk; the interface says what each choice means (permissions, storage limit, personal folders, apps).
- **USB sticks and disks:** mounted automatically at `/mnt/usb-<name>` when plugged in (FAT32, exFAT, NTFS, ext4, Btrfs), visible in the file browser for admins, **Safely remove** button, **Format** with exFAT, FAT32, NTFS or ext4. The disks in the bays are never touched by this.
- Tools on board: mkfs for Btrfs, exFAT, FAT and NTFS.
- **System → Time:** time zone, NTP on/off with own time servers (e.g. the router), *sync now*, set the clock by hand (or take the time of the browser); the battery clock of the box is set too.
- Page addresses in English (`#/storage`, `#/shares/users`, `#/system/time` …); old German links and app shortcuts are redirected.
- **10 languages:** English, German, Chinese, Hindi, Spanish, French, Arabic (right to left), Bengali, Portuguese and Russian. Translations other than English/German by AI – corrections welcome.
- **Scheduled tasks for apps** (permission `cron`): an app can declare tasks in its `app.json` (script from the package, schedule, time limit). They run as the app's own restricted user (`app-<id>`), only in its data folder, at most every 5 minutes and up to 5 per app. The install dialog lists the permissions; *Apps → Tasks* changes the schedule, switches tasks on/off, runs them now and shows the last log.

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
