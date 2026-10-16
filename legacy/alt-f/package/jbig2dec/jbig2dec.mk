################################################################################
#
# jbig2dec
#
###############################################################################

JBIG2DEC_VERSION = 0.19
JBIG2DEC_SITE = https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs9530

JBIG2DEC_INSTALL_STAGING = YES
# tarball is missing install-sh, install.sh, or shtool
JBIG2DEC_AUTORECONF = YES

$(eval $(call AUTOTARGETS,package,jbig2dec))
