# How ShareOS was built – an AI development log

*Deutsche Version: [ENTWICKLUNG.md](ENTWICKLUNG.md)*

ShareOS was developed almost entirely by an AI: **Claude** (Anthropic).
Jan started the project and steered it as a "vibe coder": he set the goals,
made the fundamental decisions and tried everything on the real hardware.
The analysis, the architecture, all of the code, the builds, the tests, the
debugging and this documentation come from Claude.

This document records, with timestamps, how that went. It shows how far an
AI got in October 2026 with real embedded development: old hardware, a
bootloader that must not be changed, and no debugger except a serial console.

![Timeline](images/zeitstrahl.png)

*Each dot is a commit (times in CEST). Generated from the git history by
`scripts/zeitstrahl.py`.*

## Who did what

| | Jan (initiator) | Claude (AI) |
|---|---|---|
| Goals & direction | Modernise Alt-F, a web UI in the style of his intranet, updates from GitHub, cloud, Paperless | Proposals with trade-offs (OpenWrt vs. Alt-F base, CGI vs. rpcd/ucode, partitioning) |
| Decisions | "Replace the old UI completely", "foundation first", "no OpenWrt", "no soldering", a wizard *and* a manual path | – |
| Code | 1 commit: importing Alt-F | 26 commits, about 5,500 new lines (build system, device tree, init, updater, backend, web UI, tests, docs) |
| Hardware | Connected the serial adapter, drove U-Boot, ran commands, sent back logs, installed the disks | Specified every command, read every log, found the causes |
| Tests | The real box (DNS-320L rev A3) | Emulator (qemu-user), test suites with a simulated box and virtual disks |

Once, "Konrad", Jan's local Claude instance, also helped: it looked directly on
the box for why the web server was not running.

## Timeline

### Friday, 16 Oct 2026 – from concept to a new base

| Time | Event |
|---|---|
| ~16:00 | Jan creates the project and imports Alt-F (r3935) into the repo as ShareOS. |
| ~16:20 | **UI concept**: Claude analyses Alt-F's 178 CGI scripts and groups them into 8 areas. The design takes its style from Jan's Skynet intranet. |
| ~16:55 | **Modernisation plan**: inventory (buildroot 2009, kernel 4.14 EOL, uClibc). Decision with Jan: modernise the Alt-F base and adopt OpenWrt's operating model (UCI, ubus, rpcd, ucode), because OpenWrt itself could only be installed through the serial console. |
| 17:10 | **New build base**: buildroot 2026.02 LTS as BR2_EXTERNAL, GCC 14, musl, kernel 6.18 with a ported DNS-320L device tree. |
| 19:10 | The kernel is too big (4.2 MB); the stock U-Boot only loads 3 MB. With xz and a leaner config it fits (2.1 MB). |
| 19:54 | Test through Alt-F's "TryIt"/kexec: the box hangs, even with Alt-F's own kernel. Claude finds the Alt-F author's confirmation that kexec does not work on the DNS-320L. **No way forward without a serial console.** |
| 21:25 | **Core stack**: UCI, ubus, rpcd with a ucode plugin, uhttpd and an updater for GitHub releases, fully tested in the emulator. |

### Saturday, 17 Oct 2026 – on the real hardware

| Time | Event |
|---|---|
| ~11:00 | Jan connects a USB-TTL adapter to the unpopulated header JP1, without soldering. Claude guides him through the pinout, swapped RX/TX wires and a loose ground. |
| ~12:15 | Stopping autoboot does not work. Claude finds the D-Link quirk in the U-Boot code: **space, then 1**. |
| ~12:30 | TFTP timeouts: the cause is the firewall (ufw) on Jan's PC. |
| 12:44 | **ShareOS boots on the box for the first time**, from RAM, without flashing anything. Gigabit, MAC address, fan, temperature, buttons and the web interface all work. |
| 12:57 | **UBI layout**: the system as squashfs, settings as a UBIFS overlay, a small initramfs with a rescue mode. |
| 13:48 | System written to flash. The settings survive a reboot. The fix for a clean shutdown is in place. |
| 14:11 | Kernel and initramfs flashed: **the box boots ShareOS on its own**, without a PC or console. The Alt-F partitions were backed up first. |
| 14:47 | **Updater for the new layout** and **new web interface** in Skynet style. |
| 15:00–15:44 | The web interface is gone after every boot. Debugging with Jan and Konrad. Claude reproduces the crash in the emulator: every browser request with `If-Modified-Since` crashes `uhttpd` (musl `strptime` with `%Z`). Fixed with a patch. |
| 15:51 | The disks are detected. This confirms the SATA power line that was corrected during porting (gpio0 24 instead of Alt-F's gpio1 24). |
| 16:00 | **Storage**: wizard and manual management (ext4, RAID 1, SMART, spindown, swap, app area). |
| 16:45 | English interface from language files, HTTPS with a self-signed certificate, first-run wizard with Alt-F import, fan and LED settings. |
| 17:20 | The storage tests with virtual disks find a real bug: with two single disks, the second ended up under the first one's name. Fixed before it reached the box. |
| 18:13 | Everything goes to `main`; Jan creates the first release `v0.1.0-beta.1`, GitHub builds the update bundle. |
| 18:26 | The box cannot reach GitHub: "certificate is not correctly signed". Claude's first guess (the network intercepts HTTPS) is wrong – Jan's output shows Google's genuine certificate. Cause: buildroot gives curl with mbedTLS no path to the CA certificates. Workaround via `/root/.curlrc`, fix in the build. |
| 20:15 | **First online update on real hardware:** the box downloads `0.1.0-beta.1` from GitHub, verifies it, writes kernel and initramfs and installs the system on restart. The first-run wizard works without problems. |
| 20:18 | Jan's feedback: after "Install" nothing visible happens. Claude adds a progress bar with the individual steps. |
| 20:31 | New requirements from Jan: menu as in "Haupt-Funktion" (Services → Autostart, System → Network), tile/table view per section, light/dark/system, logo and browser icon in the accent colour. Network settings with automatic rollback so nobody locks themselves out. |

## Notable problems solved

- **The bootloader's 3 MB limit:** the kernel shrank from 4.2 to 2.4 MB, with drivers moved to modules. The initramfs is only 0.9 MB.
- **No flashing without a way back:** first ShareOS ran from RAM, then from the network, then the system went into flash, and the kernel came last. Every step had a way back (Alt-F backup, D-Link rescue system, rescue mode).
- **U-Boot without documentation:** Claude worked out the abort sequence and the fallback to the rescue system on a broken image from the bootloader's behaviour and memory dump.
- **A hardware detail in the device tree:** Alt-F switched the SATA power through the wrong GPIO controller. Claude caught it while porting; the disks confirmed it.
- **Changing the network without locking yourself out:** a new IP takes effect at once, but the box waits 2 minutes for a confirmation from the new address. If none comes, it restores the old settings (as OpenWrt does). The web interface opens the new address itself and confirms.
- **A crash that only happened in a real browser:** the safeguard (automatic uhttpd restart, logging) came first. The actual cause was a bug in the C library, which Claude reproduced in the emulator and worked around.

## The web interface

The default is the dark blue theme with the logo. Light, dark or "same as the
operating system" and the accent colours blue, green, red and white apply to
all users. The logo and the browser icon take on the accent colour; the logo
can be switched off. Every section with tiles has a switch for a table view at
the right of its heading. The interface is available in German and English.

| Overview (English) | Storage wizard (English) |
|---|---|
| ![Overview](images/gui-en-overview.png) | ![Wizard](images/gui-en-wizard.png) |

| Login | Storage (mirror in initial sync) |
|---|---|
| ![Login](images/gui-login.png) | ![Storage](images/gui-speicher.png) |

| Firmware update | Appearance, language, logo |
|---|---|
| ![Firmware](images/gui-firmware.png) | ![Appearance](images/gui-darstellung.png) |

| Network with rollback, HTTPS | Services → Autostart |
|---|---|
| ![Network](images/gui-en-network.png) | ![Autostart](images/gui-en-autostart.png) |

| Table view | Accent colours, light and dark |
|---|---|
| ![Table view](images/gui-tabelle.png) | ![Colours](images/gui-farben.png) |

| Update with progress | Phone |
|---|---|
| ![Update](images/gui-update-progress.png) | ![Phone](images/gui-handy.png) |

*Screenshots with sample data (`tests/mock-ubus.py`): two 4 TB disks as a
mirror and an update available.*

## Numbers (as of 17 Oct 2026, 16:00)

- Working time: about 6 hours on Friday and 5 hours on Saturday
- 27 commits, 26 of them by Claude
- about 5,500 new lines: build/board 1,300, backend + web UI 2,900, tests 370, docs 500
- 18 updater tests (including a complete install on a simulated box), 21 interface checks in the ARM emulator, storage tests with virtual disks
- 0 solder joints, 0 bricked boxes

## How the work was done

Jan wrote in a chat, in German, what he wanted or what he was seeing; often
that was just a pasted console log. Claude worked in a cloud environment with
the repository: it built the firmware, tested it in the emulator, pushed to
GitHub and sent Jan the finished images with exact step-by-step instructions.
Everything that changed the box (flashing, erasing disks) happened only after
Jan's explicit OK.
