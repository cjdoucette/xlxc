TARGETS = console-setup alsa-utils mountkernfs.sh resolvconf ufw pppd-dns hostname.sh plymouth-log apparmor x11-common udev keyboard-setup mountdevsubfs.sh brltty procps networking hwclock.sh checkroot.sh urandom mountall.sh checkfs.sh checkroot-bootclean.sh bootmisc.sh kmod mountnfs.sh mountall-bootclean.sh mountnfs-bootclean.sh
INTERACTIVE = console-setup udev keyboard-setup checkroot.sh checkfs.sh
udev: mountkernfs.sh
keyboard-setup: mountkernfs.sh udev
mountdevsubfs.sh: mountkernfs.sh udev
brltty: mountkernfs.sh udev
procps: mountkernfs.sh udev
networking: resolvconf mountkernfs.sh urandom procps
hwclock.sh: mountdevsubfs.sh
checkroot.sh: hwclock.sh keyboard-setup mountdevsubfs.sh hostname.sh
urandom: hwclock.sh
mountall.sh: checkfs.sh checkroot-bootclean.sh
checkfs.sh: checkroot.sh
checkroot-bootclean.sh: checkroot.sh
bootmisc.sh: checkroot-bootclean.sh mountall-bootclean.sh mountnfs-bootclean.sh udev
kmod: checkroot.sh
mountnfs.sh: networking
mountall-bootclean.sh: mountall.sh
mountnfs-bootclean.sh: mountnfs.sh
