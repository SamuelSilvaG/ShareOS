#############################################################
#
# gnupg
#
############################################################

GNUPG_VERSION:=1.4.22
#GNUPG_VERSION:=2.2.1
#GNUPG_VERSION:=2.0.28
GNUPG_SOURCE:=gnupg-$(GNUPG_VERSION).tar.bz2
GNUPG_SITE:=ftp://ftp.gnupg.org/gcrypt/gnupg

GNUPG_DEPENDENCIES = readline libusb libiconv

$(eval $(call AUTOTARGETS,package,gnupg))
