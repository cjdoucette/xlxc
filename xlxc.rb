#
# xlxc: a class for XIA LXC container defintions
#
# Author: Cody Doucette <doucette@bu.edu>
#


class XLXC

  # Directory where containers are kept on host.
  LXC = "/var/lib/lxc"

  # Directories that are bind mounted (read-only) from the host.
  BIN   = "/bin"
  LIB64 = "/lib64"
  VAR   = "/var"
  LIB   = "/lib"
  SBIN  = "/sbin"
  USR   = "/usr"

  # In order to have access to special character and block files,
  # we copy the host's /dev directory to a local copy and then
  # bind mount that local copy to the containers.
  SYSTEM_DEV = "/dev"

  # Default configuration data for each LXC container. More
  # configuration data is appended in xlxc-create.
  LXC_CONFIG_TEMPLATE =
"lxc.network.type=veth
lxc.network.flags=up

lxc.devttydir=lxc
lxc.tty=4
lxc.pts=1024
lxc.cap.drop=sys_module mac_admin mac_override
lxc.pivotdir=lxc_putold

lxc.cgroup.devices.deny = a

# Allow any mknod (but not using the node)
lxc.cgroup.devices.allow = c *:* m
lxc.cgroup.devices.allow = b *:* m
# /dev/null and zero
lxc.cgroup.devices.allow = c 1:3 rwm
lxc.cgroup.devices.allow = c 1:5 rwm
# consoles
lxc.cgroup.devices.allow = c 5:1 rwm
lxc.cgroup.devices.allow = c 5:0 rwm
#lxc.cgroup.devices.allow = c 4:0 rwm
#lxc.cgroup.devices.allow = c 4:1 rwm
# /dev/{,u}random
lxc.cgroup.devices.allow = c 1:9 rwm
lxc.cgroup.devices.allow = c 1:8 rwm
lxc.cgroup.devices.allow = c 136:* rwm
lxc.cgroup.devices.allow = c 5:2 rwm
# rtc
lxc.cgroup.devices.allow = c 254:0 rwm
#fuse
lxc.cgroup.devices.allow = c 10:229 rwm
#tun
lxc.cgroup.devices.allow = c 10:200 rwm
#full
lxc.cgroup.devices.allow = c 1:7 rwm
#hpet
lxc.cgroup.devices.allow = c 10:228 rwm
#kvm
lxc.cgroup.devices.allow = c 10:232 rwm
lxc.arch=amd64
"

  # Data to be entered into each container's fstab file.
  FSTAB_TEMPLATE =
"proc         proc         proc  nodev,noexec,nosuid 0 0
sysfs        sys          sysfs defaults 0 0
"

  # File that holds interface information.
  INTERFACES_FILE = "/etc/network/interfaces"

  # Interface file with a format tag to make each
  # container's IP address unique.
  INTERFACES_TEMPLATE =
"auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address 192.168.0.%d
netmask 255.255.255.0
network 192.168.0.0
broadcast 192.168.0.255
gateway 192.168.0.1
"

end
