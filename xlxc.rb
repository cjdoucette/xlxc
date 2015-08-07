#
# xlxc: a class for XIA LXC container defintions
#
# Author: Cody Doucette <doucette@bu.edu>
#


class XLXC

  # Directory where containers are kept on host.
  LXC = "/var/lib/lxc"

  # Directories that are bind mounted (read-only) from the host.
  BIND_MOUNTED_DIRECTORIES = [
    "/bin",
    "/lib64",
    "/lib",
    "/sbin",
    "/usr"
  ]

  # Bind mount a source file to a destination file.
  #
  def self.bind_mount(src, dst, isDir, readOnly)
    if isDir
      FileUtils.mkdir_p(dst)
    else
      FileUtils.touch(dst)
    end

    `mount --rbind #{src} #{dst}`

    if readOnly 
      `mount -o remount,ro #{dst}`
    end
  end

  # Set up the network for this bridge. This involves re-creating the
  # Ethernet bridge (if necessary) and allocating an IP address.
  #
  def self.setup_net(name)
    bridge = XLXC_BRIDGE.get_bridge(name)
    cidr = XLXC_BRIDGE.get_bridge_cidr(bridge)
    iface = XLXC_BRIDGE.get_bridge_iface(bridge)

    # If this interface is not up, create it.
    interfaces = Dir.entries(XLXC_BRIDGE::INTERFACES)
    if !interfaces.include?(bridge)
      XLXC_BRIDGE.add_interface(bridge, cidr, iface)
    end

    if XLXC_BRIDGE.get_ip_addr(name, bridge) == nil
      XLXC_BRIDGE.alloc_ip_address_from_bridge(name, bridge)
    end
  end

  # Perform bind mounts necessary to run container.
  #
  def self.setup_fs(name)
    rootfs = File.join(LXC, name, "rootfs")

    # Bind mount (read-only) directories from host.
    for dir in BIND_MOUNTED_DIRECTORIES
      if !Dir.exists?(File.join(rootfs, dir)) ||
        Dir.entries(File.join(rootfs, dir)).size() <= 2
        bind_mount(dir, File.join(rootfs, dir), true, true)
      end
    end
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
    address %s 
    netmask %s
    network %s
    broadcast %s
    gateway %s
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
