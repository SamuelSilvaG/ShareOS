#############################################################
#
# gptfdisk
#
#############################################################

GPTFDISK_VERSION:=1.0.10
GPTFDISK_SOURCE:=gptfdisk-$(GPTFDISK_VERSION).tar.gz
GPTFDISK_SITE:=$(BR2_SOURCEFORGE_MIRROR)/project/gptfdisk/gptfdisk/$(GPTFDISK_VERSION)

GPTFDISK_INSTALL_STAGING = NO
GPTFDISK_LIBTOOL_PATCH = NO

GPTFDISK_DIR:=$(BUILD_DIR)/gptfdisk-$(GPTFDISK_VERSION)

GPTFDISK_CFLAGS = CFLAGS = "$(TARGET_CFLAGS) -Wall $(BR2_PACKAGE_GPTFDISK_OPTIM)"
GPTFDISK_CXXFLAGS = CXXFLAGS = "$(TARGET_CXXFLAGS) -Wall $(BR2_PACKAGE_GPTFDISK_OPTIM)"
GPTFDISK_LDFLAGS = LDFLAGS = "$(TARGET_LDFLAGS)"

GPTFDISK_DEPENDENCIES = popt libuuid ncurses
GPTFDISK_MAKE_OPT = sgdisk gdisk cgdisk fixparts

$(eval $(call AUTOTARGETS,package,gptfdisk))

$(GPTFDISK_TARGET_CONFIGURE):
	echo CC = $(TARGET_CC) >> $(GPTFDISK_DIR)/Makefile
	echo CXX = $(TARGET_CXX) >> $(GPTFDISK_DIR)/Makefile
	echo $(GPTFDISK_CFLAGS) >> $(GPTFDISK_DIR)/Makefile
	echo $(GPTFDISK_CXXFLAGS) >> $(GPTFDISK_DIR)/Makefile
	echo $(GPTFDISK_LDFLAGS) >> $(GPTFDISK_DIR)/Makefile
	sed -i 's/ncursesw/ncurses/' $(GPTFDISK_DIR)/Makefile
	sed -i 's/__APPLE__/__UCLIBC__/' $(GPTFDISK_DIR)/gptcurses.cc
	touch $@

$(GPTFDISK_TARGET_INSTALL_TARGET):
ifeq ($(BR2_PACKAGE_GPTFDISK_SGDISK),y)
	cp $(GPTFDISK_DIR)/sgdisk $(TARGET_DIR)/usr/sbin
endif
ifeq ($(BR2_PACKAGE_GPTFDISK_GDISK),y)
	cp $(GPTFDISK_DIR)/gdisk $(TARGET_DIR)/usr/sbin
endif
ifeq ($(BR2_PACKAGE_GPTFDISK_FIXPARTS),y)
	cp $(GPTFDISK_DIR)/fixparts $(TARGET_DIR)/usr/sbin
endif
ifeq ($(BR2_PACKAGE_GPTFDISK_CGDISK),y)
	cp $(GPTFDISK_DIR)/cgdisk $(TARGET_DIR)/usr/sbin
endif
	touch $@
