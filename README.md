# ShareOS

ShareOS is a free, open source alternative firmware for the D-Link
DNS-320L (and, later, the DNS-320/321/323/325/327L, DNR-322L and
compatible NAS boxes).

It is a fork of [Alt-F](http://sourceforge.net/projects/alt-f) by João
Cardoso. All credit for the original design, the hardware support and
years of work goes to the Alt-F project — see [LICENSE](LICENSE) and
[COPYING](COPYING) for the GPLv2 terms.

## Status: phase 1 – new build base

ShareOS is being rebuilt on a current, maintainable base while keeping
what made Alt-F easy to use: the stock U-Boot, the stock flash layout and
installing from the vendor web interface.

| | Alt-F (legacy) | ShareOS |
|---|---|---|
| Build system | buildroot 2009.08 fork | buildroot 2026.02 LTS, `BR2_EXTERNAL` tree |
| Toolchain | GCC 7.4, uClibc-ng | GCC 14, musl |
| Kernel | 4.14 (EOL) | 6.18 LTS |
| Configuration | scattered files, shell CGIs | UCI + ubus/rpcd/ucode (planned) |
| Updates | manual upload | GitHub Releases (planned) |

The phase-1 image is a **minimal test system** (SSH, hardware check) to
validate the new kernel and board support on real hardware. It has no web
interface yet. See [docs/TEST-PHASE1.md](docs/TEST-PHASE1.md) for how to
try it from Alt-F *without flashing*.

## Layout

```
configs/                 buildroot defconfigs (shareos_<board>_defconfig)
board/dlink/dns320l/     device tree, kernel fragment, rootfs overlay, image scripts
package/                 ShareOS buildroot packages
src/alt-f-utils/         Alt-F device tools (MCU daemon, dns323-fw, sysctrl)
patches/                 hashes/patches for buildroot packages
scripts/                 helper scripts
legacy/alt-f/            the original Alt-F tree, kept for reference
```

## Building

See [docs/BUILD.md](docs/BUILD.md). In short:

```sh
make dns320l
# -> output/dns320l/images/ShareOS-<version>-DNS-320L-rev-Ax.bin
```
