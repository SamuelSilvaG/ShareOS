# ShareOS

ShareOS is a free, open source alternative firmware for the D-Link
DNS-320/320L/321/323/325/327L, DNR-322L and compatible NAS boxes.

It is a fork of [Alt-F](http://sourceforge.net/projects/alt-f) (by João
Cardoso), created because the original project's firmware support from
D-Link ended and the Alt-F community firmware itself is no longer actively
maintained. All credit for the original design and years of work goes to
the Alt-F project and its author — see [LICENSE](LICENSE) and
[COPYING](COPYING) for the full GPLv2 terms this code is distributed under.

## What changed from Alt-F

This is primarily a rebrand at this point: the boot banner, web admin UI,
firmware image naming/detection, package-manager mount point (`/ShareOS`
instead of `/Alt-F`), and related internal naming were updated throughout.
The underlying buildroot-based system, kernel, and hardware support are
unchanged from Alt-F r3935 (trunk).

A few places intentionally still point at the original Alt-F project,
since ShareOS doesn't have its own release channel yet:

- The optional "install Debian alongside ShareOS" feature
  (`customroot/usr/www/cgi-bin/debian_proc.cgi`) downloads a real Alt-F
  firmware image to kexec back into after leaving Debian.
- The QEMU test script (`qemu-ShareOS.sh`) downloads Alt-F's original
  simulator kernel/rootfs images.
- `fixup`'s `FIXSITE` still points at Alt-F's hosted fix repository.

These can be pointed at ShareOS's own GitHub releases once any exist.

## Documentation

- [README.INSTALL](README.INSTALL) — flashing instructions
- [README.USE](README.USE) — using the web admin interface
- [README.BUILD](README.BUILD) — building firmware images from source
- [NEWS](NEWS) / [CHANGES](CHANGES) — Alt-F's historical changelog, kept
  as-is for the project history prior to this fork
