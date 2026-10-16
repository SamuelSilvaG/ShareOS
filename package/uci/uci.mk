################################################################################
#
# uci
#
################################################################################

UCI_VERSION = 74f6277aabffc943d026f406df57c22595134c42
UCI_SITE = https://github.com/openwrt/uci
UCI_SITE_METHOD = git
UCI_LICENSE = LGPL-2.1
UCI_INSTALL_STAGING = YES
UCI_DEPENDENCIES = libubox
UCI_CONF_OPTS = -DBUILD_LUA=OFF -DBUILD_STATIC=OFF

$(eval $(cmake-package))
