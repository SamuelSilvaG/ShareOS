#############################################################
#
# dns-323-321-compat
#
#############################################################

# this is a dummy target just to have BR2_PACKAGE_DNS_323_321_COMPAT defined

DNS_323_321_COMPAT_VERSION = 0.1

dns-323-321-compat: at cifs-utils nfs-utils inadyn-mt openssh-sftp vsftpd stunnel rsync ntfs-3g smartmontools samba4
