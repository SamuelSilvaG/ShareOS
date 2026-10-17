#/bin/bash

#download br-2019 if not exists
#make sdk
#untar the tarball
#cd to created dir
#run ./relocate-sdk.sh

BR_VER=2019.02.8
BR_SITE=https://buildroot.org/downloads
BR_TB=buildroot-$BR_VER.tar.bz2

if test "$(dirname $0)" != "."; then
        echo "mktc: This script must be run in the root of the tree."
        exit 1;
fi

if test -z "$BLDDIR" -o ! -f .config; then
        echo "mktc: Run '. exports [board] [build dir]' first."
        exit 1
fi

#. .config 2> /dev/null

if ! test -f dl/$BR_TB; then
	if ! wget $BR_SITE/$BR_TB -P dl/; then
		echo "mktc: can't download $BR_TB from ${BR_SITE}."
		exit 1
	fi
fi

#BR_VER=$(echo $BR_TB | sed -n 's/.*-\(.*\).tar.*/\1/p')

if ! test -d $BLDDIR/br-$BR_VER; then
	mkdir -p $BLDDIR/br-$BR_VER
	if ! tar --strip-components=1 -C $BLDDIR/br-$BR_VER -xjf dl/$BR_TB; then
		echo "mktc: extraction of $BR_TB failed."
		exit 1
	fi
fi

if ! test -f $BLDDIR/br-$BR_VER/.config; then
	if ! test -f local/buildroot-$BR_VER.config; then
		echo "mktc: No local/buildroot-$BR_VER.config"
		exit 1
	else
		cp local/buildroot-$BR_VER.config $BLDDIR/br-$BR_VER/.config
	fi
fi

if ! test -f $BLDDIR/br-$BR_VER/uclibc-ng.config; then
	if ! test -f local/uclibc-1.0.31.config; then
		echo "mktc: No local/uclibc-1.0.31.config"
		exit 1
	else
		cp local/uclibc-1.0.31.config $BLDDIR/br-$BR_VER/uclibc-ng.config
	fi
fi

cd $BLDDIR/br-$BR_VER

# use uclibc-1.0.44
if ! grep -q "UCLIBC_VERSION = 1.0.44" package/uclibc/uclibc.mk; then
	(cd package/uclibc/
	sed -i 's/UCLIBC_VERSION =.*$/UCLIBC_VERSION = 1.0.44/' uclibc.mk
	rename .patch .patch- *.patch
	echo "sha256  7df9d987955827382f1c2400da513456becbb6f868bdfd37737265f1cbeec994  uClibc-ng-1.0.44.tar.xz" >> uclibc.hash
	)
fi

if ! test -h dl; then
	if ! test -e ../../dl; then
		mkdir -p ../../dl
	fi
	ln -sf ../../dl dl
fi

# make olddefconfig for buildroot and uclibc?! 'make toolchain' does it for uclibc

if ! test -f output/host/bin/arm-linux-gcc; then
	make V=1 toolchain 
fi

cd ../..

# set PATH=$BLDDIR/br-$BR_VER/output/host/bin/. 'exports' does it
#FIXME: YES, but does not propagate back to environment. exports is sourced!
# This script needs to be part of the build Makefiles

# fix BR2_TOOLCHAIN_EXTERNAL_PATH= in .config (without changing its date)
# cstamp=$(mktemp)
# sed -i 's|^BR2_TOOLCHAIN_EXTERNAL_PATH=.*|BR2_TOOLCHAIN_EXTERNAL_PATH='$BLDDIR/br-$BR_VER'/output/host|' .config
# touch -r $cstamp .config
# rm $cstamp

# and BR2_TOOLCHAIN_EXTERNAL_PREFIX= also? Not needed
