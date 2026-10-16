Quick Instructions for RC4 and later. For the full documentation read the Alt-F Wiki
(ShareOS is a fork of Alt-F and hasn't written its own build docs yet).

Checkout the development tree:

	git clone https://github.com/UniqueDroid/ShareOS

(the original Alt-F tree this was forked from can still be found at
http://alt-f.googlecode.com/svn/tags/Release-0.1RC4, for reference)

Then,
  
	cd alt-f-read-only			# change to the checkout directory
	. exports dns323			# defines the firmware to be built and some needed variables
	make >& build-dns323.log	# make it all, logging to build-dns323.log
	./mkinitramfs.sh			# create the root filesystem
	./mkfw.sh					# create the firmware files

'exports' must be sourced, not executed.
Some mk*.sh scripts will ask for the root password; this is needed to
mount the generated ext2 rootfs as a loop device and manipulate it. See
the source.

When finished, you should find:

-in $BINARIES, the kernel, "zImage", the root filesystem image, "rootfs.arm.ext2",
 and the firmware files, "ShareOS-RC4-<model>.bin"
-in $ROOTFS you will find the directory structure used to create the
 root filesystem image, "rootfs.arm.ext2".
-in $KERNEL the built linux kernel

