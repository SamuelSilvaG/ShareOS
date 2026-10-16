#############################################################
#
# exfatprogs
#
#############################################################

EXFATPROGS_VERSION:=1.1.3
EXFATPROGS_SOURCE:=exfatprogs-$(EXFATPROGS_VERSION).tar.gz
EXFATPROGS_SITE:=https://github.com/exfatprogs/exfatprogs/releases/download/$(EXFATPROGS_VERSION)

EXFATPROGS_LIBTOOL_PATCH = NO
EXFATPROGS_AUTORECONF = NO

# not compilable with gcc-4.3 (runtime errors), using gcc-7.4.0 from Buildroot 2019.02.8
# toolchain installed at /Alt-F/br-2019-sdk or $(shell realpath $(TOPDIR))/../br-2019-sdk/bin)
#
# using  toolchain to configure:
# CC=arm-linux-gcc ./configure --target=arm-linux --host=arm-linux --build=x86_64-pc-linux-gnu
# --with-sysroot=/Alt-F/br-2019-sdk/arm-buildroot-linux-uclibcgnueabi/sysroot 
# PATH set to Alt-F/br-2019-sdk/bin
#
# to force static linking (compile toolchain libs are != from runtime libs),
# use AM_LDFLAGS="-all-static" in make environment ...

#BR_SDK_PATH=$(shell realpath $(TOPDIR)/../br-2019-sdk)

$(eval $(call AUTOTARGETS,package,exfatprogs))

#		--with-sysroot=$(BR_SDK_PATH)/arm-buildroot-linux-uclibcgnueabi/sysroot 
#		
# $(EXFATPROGS_TARGET_CONFIGURE):
# 	if ! test -x $(BR_SDK_PATH)/bin/arm-linux-gcc; then \
# 		echo -e "\n\
# 		*********************************************************\n\
# 		* You have to install a more recent gcc cross-compiler, *\n\
# 		* see notes at package/exfatprogs/exfatprogs.mk         *\n\
# 		*********************************************************"; \
# 		exit 1; \
# 	fi
# 	(cd $(EXFATPROGS_DIR); rm -rf config.cache; \
# 		PATH=$(BR_SDK_PATH)/bin:/bin:/usr/bin \
# 		CC=arm-linux-gcc \
# 		CFLAGS="$(TARGET_OPTIMIZATION) \
# 		-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 "\
# 		./configure \
# 		--target=$(GNU_TARGET_NAME) \
# 		--host=$(GNU_TARGET_NAME) \
# 		--build=$(GNU_HOST_NAME) \
# 		--prefix=/usr \
# 	)
# 	touch $@
# 
# $(EXFATPROGS_TARGET_BUILD):
# 	PATH=$(BR_SDK_PATH)/bin:/bin:/usr/bin \
# 	AM_LDFLAGS="-all-static" \
# 	$(MAKE) -C $(EXFATPROGS_DIR)
# 	touch $@
