# ShareOS

ShareOS is a free, open source alternative firmware for the D-Link
DNS-320L (and, later, the DNS-320/321/323/325/327L, DNR-322L and
compatible NAS boxes).

It is a fork of [Alt-F](http://sourceforge.net/projects/alt-f) by João
Cardoso. All credit for the original design, the hardware support and
years of work goes to the Alt-F project — see [LICENSE](LICENSE) and
[COPYING](COPYING) for the GPLv2 terms.

> **Built by an AI.** Apart from importing Alt-F, ShareOS was developed by
> Claude (Anthropic): architecture, all code, builds, tests and docs. Jan
> started the project, made the decisions and tested on the real box.
> Timeline with timestamps and screenshots:
> **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** ([Deutsch](docs/ENTWICKLUNG.md)).
>
> Testing and installing: [docs/TESTING.md](docs/TESTING.md) ([Deutsch](docs/TESTEN.md)).
> Translating the web interface: [docs/TRANSLATING.md](docs/TRANSLATING.md).

![ShareOS web interface](docs/images/gui-uebersicht.png)

## Status: public test versions (beta) for the DNS-320L

ShareOS runs from flash on the DNS-320L (kernel, initramfs and the system in
UBI with a persistent overlay for settings and packages). Test releases
(`v0.1.0-beta.x`, pre-releases, for test devices only) are published on
[GitHub Releases](https://github.com/UniqueDroid/ShareOS/releases); a running
ShareOS updates itself from there.

ShareOS is built on a current, maintainable base while keeping what made
Alt-F easy to use: the stock U-Boot and the stock flash layout.

| | Alt-F (legacy) | ShareOS |
|---|---|---|
| Build system | buildroot 2009.08 fork | buildroot 2026.02 LTS, `BR2_EXTERNAL` tree |
| Toolchain | GCC 7.4, uClibc-ng | GCC 14, musl |
| Kernel | 4.14 (EOL) | 6.18 LTS |
| Configuration | scattered files, shell CGIs | UCI + ubus/rpcd/ucode |
| Web interface | shell CGIs | new interface (light/dark, accent colours, tiles or tables), installable as an app |
| Updates | manual upload | GitHub Releases, checked every 6 hours, verified, with progress – tested on hardware |
| Shares | Samba 3.6 | ksmbd (SMB 2/3), NFS v4 |

What is in it:

- **Storage:** setup assistant with a choice of ext4, Btrfs, exFAT or NTFS, RAID 1, SMART, disk standby, swap
- **USB drives:** mounted when plugged in, *safely remove*, formatting with exFAT, FAT32, NTFS or ext4
- **Shares and users:** SMB/NFS shares with permissions per user and group, storage limit per user, one account for shares, web interface and apps, import of Alt-F users with their passwords
- **"My ShareOS":** users with web access get their own area (storage, shares, password, look, file browser, Paperless, cloud)
- **File browser:** admins for all drives, users for their personal folder (per user)
- **Apps:** store with one-click install from [ShareOS-Apps](https://github.com/UniqueDroid/ShareOS-Apps) (web apps such as Webpad; own apps and catalogs possible), visibility per user
- **Cloud sync** with rclone (Nextcloud/WebDAV, S3, SFTP, Google Drive and more) for the device and per user
- **Paperless-ngx:** inbox folders per user or shared (e.g. for a scanner)
- **Firmware:** online updates from GitHub, first installation from the Alt-F/D-Link web interface (system from USB stick or GitHub), back to Alt-F by uploading its `.bin`
- **System:** first-run assistant, network with automatic rollback, HTTPS (own certificate possible), services and autostart, fan/LEDs, logs, settings backup (JSON, optionally AES-256), status address for widget apps
- English and German interface (more languages: [docs/TRANSLATING.md](docs/TRANSLATING.md))

**Installing:** flash the ShareOS `.bin` from the Alt-F or D-Link firmware
page; ShareOS then installs its system from a USB stick or from GitHub by
itself (new in 0.1.0-beta.7, hardware test pending). The tested way over the
serial console (TFTP boot) stays available. **Back to Alt-F** works from the
ShareOS firmware page. Details: [docs/TESTING.md](docs/TESTING.md),
[docs/HARDWARE-DNS320L.md](docs/HARDWARE-DNS320L.md). The backend can be run on
a build host with qemu (`tests/run-stack-qemu.sh`), the web interface with
sample data via `tests/mock-ubus.py`.

Next: hardware tests of the current betas, notifications, native apps
(MiniDLNA, Transmission, Syncthing …) in the same store, more devices (DNS-320/325/327L), a public beta.

## Layout

```
configs/                 buildroot defconfigs (shareos_<board>_defconfig)
board/dlink/dns320l/     device tree, kernel fragment, rootfs overlay, image scripts
package/                 ShareOS buildroot packages
src/alt-f-utils/         Alt-F device tools (MCU daemon, dns323-fw, sysctrl)
patches/                 hashes/patches for buildroot packages
src/shareos-core/        backend: rpcd ucode plugin, updater, UCI defaults, init scripts
tests/                   host and emulator tests (updater, network, users/shares, storage, cloud/Paperless, qemu stack), UI mock
scripts/                 helper scripts
legacy/alt-f/            the original Alt-F tree, kept for reference
```

## Building

See [docs/BUILD.md](docs/BUILD.md). In short:

```sh
make dns320l
# -> output/dns320l/images/ShareOS-<version>-DNS-320L-rev-Ax.bin
```
