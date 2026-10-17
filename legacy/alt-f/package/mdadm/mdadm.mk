#############################################################
#
# mdadm
#
#############################################################

MDADM_VERSION:=4.3

MDADM_SOURCE:=mdadm-$(MDADM_VERSION).tar.xz
MDADM_SITE:=$(BR2_KERNEL_MIRROR)/linux/utils/raid/mdadm

MDADM_MAKE_OPT = CXFLAGS="$(TARGET_CFLAGS) -Wno-error -DNO_LIBUDEV -DNO_DLM -DNO_COROSYNC -DUCLIBC -DHAVE_STDINT_H $(BR2_PACKAGE_MDADM_OPTIM)" \
CC=$(TARGET_CC) \
RUN_DIR="/var/run/mdadm" \
CWFLAGS="-Wall -Werror -Wstrict-prototypes -Wextra -Wno-unused-parameter -Wformat -Wformat-security -Werror=format-security -fPIE -Warray-bounds"

MDADM_INSTALL_TARGET_OPT = $(MDADM_MAKE_OPT) DESTDIR=$(TARGET_DIR) install

$(eval $(call AUTOTARGETS,package,mdadm))

$(MDADM_TARGET_CONFIGURE):
	touch $@
