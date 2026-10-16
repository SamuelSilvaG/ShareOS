# Building ShareOS

ShareOS is a buildroot `BR2_EXTERNAL` tree. The top-level `Makefile`
downloads the pinned buildroot release (checksum-verified) and drives it.

## Requirements

A Linux host (Debian/Ubuntu tested) with:

```sh
sudo apt-get install build-essential bc bison flex cpio rsync unzip file wget \
                     libssl-dev libncurses-dev python3
```

About 10 GB disk. A first build takes roughly 1 hour on 4 cores (most of
it is the cross toolchain).

## Commands

```sh
make dns320l                    # full build
make dns320l-menuconfig         # buildroot options
make dns320l-linux-menuconfig   # kernel options
make dns320l-savedefconfig      # write changes back to configs/
make clean                      # drop output/, keep downloads in dl/
```

Output in `output/dns320l/images/`:

| File | Content |
|---|---|
| `ShareOS-<ver>-DNS-320L-rev-Ax.bin` | firmware in the D-Link container format (kernel + initramfs) |
| `….bin.sha256` | checksum |
| `uImage`, `urootfs` | the two parts on their own |
| `zImage.kirkwood-dns320l` | kernel with appended device tree |
| `modules.tar.xz` | kernel modules (not part of the phase-1 image) |

## Size limits

The stock U-Boot reads only 3 MB of the `uImage` and of the `ramdisk`
flash partition. `post-image.sh` fails the build if either part is larger.

## CI

`.github/workflows/build.yml` builds every push. Pushing a tag `v*`
publishes the images as a GitHub Release (tags containing `-` are marked
as pre-release) — this is what the future in-GUI updater will consume.
