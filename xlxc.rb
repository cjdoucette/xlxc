#
# xlxc: a class for XIA LXC container defintions
#
# Author: Cody Doucette <doucette@bu.edu>
#


class XLXC

  LXC_FILES = [
    "/usr/lib/x86_64-linux-gnu/lxc/lxc-init",
    "/usr/lib/x86_64-linux-gnu/libseccomp.so.1",
    "/usr/lib/libapparmor.so.1",
    "/lib/x86_64-linux-gnu/libcap.so.2",
    "/usr/lib/x86_64-linux-gnu/liblxc.so.1"
  ]

  LXC_DIR  = "/usr/lib/x86_64-linux-gnu/lxc"
  KERNEL   = `uname -r`.delete("\n")
  LXC      = "/var/lib/lxc"
  MODULES  = "/lib/modules/#{KERNEL}"
  XIP      = "/sbin/xip"
  LIBXIA   = "/usr/lib/libxia.so.0"
  XIA_DATA = "/etc/xia"

  FSTAB =      "proc         proc         proc  nodev,noexec,nosuid 0 0\n" \
               "sysfs        sys          sysfs defaults 0 0\n"

  INTERFACES = "auto lo\n"                \
               "iface lo inet loopback\n" \
               "\n"                       \
               "auto eth0\n"              \
               "iface eth0 inet dhcp\n"   \

  LXC_CONFIG = "lxc.network.type=veth\n"                          \
               "lxc.network.flags=up\n"                           \
               "\n"                                               \
               "lxc.devttydir=lxc\n"                              \
               "lxc.tty=4\n"                                      \
               "lxc.pts=1024\n"                                   \
               "lxc.cap.drop=sys_module mac_admin mac_override\n" \
               "lxc.pivotdir=lxc_putold\n"                        \
               "\n"                                               \
               "lxc.cgroup.devices.deny = a\n"                    \
               "\n"                                               \
               "# Allow any mknod (but not using the node)\n"     \
               "lxc.cgroup.devices.allow = c *:* m\n"             \
               "lxc.cgroup.devices.allow = b *:* m\n"             \
               "# /dev/null and zero\n"                           \
               "lxc.cgroup.devices.allow = c 1:3 rwm\n"           \
               "lxc.cgroup.devices.allow = c 1:5 rwm\n"           \
               "# consoles\n"                                     \
               "lxc.cgroup.devices.allow = c 5:1 rwm\n"           \
               "lxc.cgroup.devices.allow = c 5:0 rwm\n"           \
               "#lxc.cgroup.devices.allow = c 4:0 rwm\n"          \
               "#lxc.cgroup.devices.allow = c 4:1 rwm\n"          \
               "# /dev/{,u}random\n"                              \
               "lxc.cgroup.devices.allow = c 1:9 rwm\n"           \
               "lxc.cgroup.devices.allow = c 1:8 rwm\n"           \
               "lxc.cgroup.devices.allow = c 136:* rwm\n"         \
               "lxc.cgroup.devices.allow = c 5:2 rwm\n"           \
               "# rtc\n"                                          \
               "lxc.cgroup.devices.allow = c 254:0 rwm\n"         \
               "#fuse\n"                                          \
               "lxc.cgroup.devices.allow = c 10:229 rwm\n"        \
               "#tun\n"                                           \
               "lxc.cgroup.devices.allow = c 10:200 rwm\n"        \
               "#full\n"                                          \
               "lxc.cgroup.devices.allow = c 1:7 rwm\n"           \
               "#hpet\n"                                          \
               "lxc.cgroup.devices.allow = c 10:228 rwm\n"        \
               "#kvm\n"                                           \
               "lxc.cgroup.devices.allow = c 10:232 rwm\n"        \
end
