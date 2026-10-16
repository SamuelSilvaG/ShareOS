#############################################################
#
# iperf3
#
#############################################################

IPERF3_VERSION:=3.9
IPERF3_SOURCE:=iperf-$(IPERF3_VERSION).tar.gz
#IPERF3_SITE:=https://github.com/esnet/iperf/archive/refs/tags
IPERF3_SITE:=https://downloads.es.net/pub/iperf

IPERF3_AUTORECONF:=NO
IPERF3_INSTALL_STAGING:=NO
IPERF3_INSTALL_TARGET:=YES
IPERF3_LIBTOOL_PATCH:=NO

IPERF3_CONF_OPT = --without-openssl --disable-shared

IPERF3_DEPENDENCIES:=uclibc

$(eval $(call AUTOTARGETS,package,iperf3))
