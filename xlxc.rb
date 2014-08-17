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
  LIB   = "/lib"
  SBIN  = "/sbin"
  USR   = "/usr"

  # Directory that contains all bridge information.
  BRIDGES = File.join(LXC, "bridges")

  # Default name for bridge to containers.
  DEF_PRIVATE_GW      = "192.168.100.1"
  DEF_PRIVATE_NETMASK = "255.255.255.0"

  # Increment the reference count to this bridge.
  def self.inc_bridge_ref(bridge)
    if !File.exists?(BRIDGES)
      `mkdir #{BRIDGES}`
    end
    count = 0

    bridge_file = File.join(BRIDGES, bridge)
    f = File.open(bridge_file, File::RDWR|File::CREAT, 0644)
    f.flock(File::LOCK_EX)
    if !f.eof?()
      count = f.readline.to_i()
    end
    `echo #{count + 1} > #{bridge_file}`
    f.close()
  end

  # Decrement the reference count to this bridge,
  # destroying it if necessary.
  def self.dec_bridge_ref(bridge)
    bridge_file = File.join(BRIDGES, bridge)
    if !File.exists?(bridge_file)
      return
    end
    f = File.open(bridge_file, File::RDWR, 0644)
    f.flock(File::LOCK_EX)
    count = f.readline.to_i()
    if count - 1 == 0
      `ifconfig #{bridge} promisc down`
      `brctl delbr #{bridge}`
      `rm #{bridge_file}`
    else
      `echo #{count - 1} > #{bridge_file}`
    end
    f.close()
  end

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

  # File that holds host information.
  HOSTS_FILE = "/etc/hosts"

  # File that holds hostname information.
  HOSTNAME_FILE = "/etc/hostname"

  # Interface file with a format tag to make each
  # container's IP address unique.
  INTERFACES_TEMPLATE =
"auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address 192.168.100.%d
netmask 255.255.255.0
network 192.168.100.0
broadcast 192.168.100.255
gateway 192.168.100.1
"

  # Hosts file with a format tag for a unique hostname.
  HOSTS_TEMPLATE =
"127.0.0.1   localhost
127.0.1.1   %s

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
"

end
