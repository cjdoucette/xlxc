#
# xlxc-create: create XIA-linux containers
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script creates and initializes a given number of IP or XIA linux
# containers. Each container uses a separate network bridge to the host.
#
# This script is based on the lxc-create and lxc-ubuntu scripts written by:
#     Daniel Lezcano <daniel.lezcano@free.fr>     (lxc-create)
#     Serge Hallyn   <serge.hallyn@canonical.com> (lxc-ubuntu)
#     Wilhelm Meier  <wilhelm.meier@fh-kl.de>     (lxc-ubuntu)
#

 
require 'fileutils'
require 'optparse'
require './xlxc'


# Directories that need to be directly copied (etc).
LOCAL_ETC = "./etc"

# Directories that are initially empty, but need to be created.
PROC      = "/proc"
SYS       = "/sys"
DEV_PTS   = "/dev/pts"
HOME      = "/home/ubuntu"
ROOT      = "/root"
VAR_RUN   = "/var/run"

# Directory that contains directories for interfaces.
INTERFACES = "/sys/class/net"

# Directories that hold XIA-related data.
XIA       = "/etc/xia"
XIA_HIDS  = File.join(XIA, "hid/prv")

# Other files that need to be created.
DEV_RANDOM   = "/dev/random"    # for HID principal in XIA
DEV_URANDOM  = "/dev/urandom"   # for HID principal in XIA

USAGE = "Usage: ruby xlxc-create.rb NAME START END GATEWAY [-rs]"


# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = USAGE

    options[:reset] = false
    opts.on('-r', '--reset', 'Reset containers and bridges') do
      options[:reset] = true
    end

    options[:script] = false
    opts.on('-s', '--script', 'Create a script for each container') do
      options[:script] = true
    end
  end

  optparse.parse!
  return options
end

# Perform error checks on the parameters of the script and options
#
def check_for_errors(name, first, last, gw, options)
  if ARGV.length != 4
    puts(USAGE)
    exit
  end

  if last < first
    puts("End parameter cannot be less than start parameter.")
    exit
  end

  # Check that user is root.
  if Process.uid != 0
    puts("xlxc-create must be run as root.")
    exit
  end

  # Check to make sure gateway exists.
  if !File.exists?(File.join(INTERFACES, gw))
    puts("Host interface #{gw} does not exist.")
    exit
  end

  # Check that user is running XIA kernel.
  # TODO Find a better way to check this.
  if !`uname -r`.include?("xia")
    puts("Must be running Linux XIA to create XIA containers.")
    exit
  end

  # Check that there are no conflicts in container names.
  for i in first..last
    container = File.join(XLXC::LXC, name + i.to_s())
    if options[:reset] && !File.exist?(container)
      puts("Container #{container} does not exist.")
    end
    if !options[:reset] && File.exist?(container)
      puts("Naming conflict: container #{container} " +
           "already exists in #{XLXC::LXC}.")
      exit
    end
  end
end

# Bind mount a source file to a destination file.
#
def bind_mount(src, dst, isDir, readOnly)
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

# Copy a default LXC configuration file and add configuration
# information for it that is specific to this container, such
# as a network interface, hardware address, and bind mounts.
#
def config_lxc(name, i)
  container_name = name + i.to_s()
  container = File.join(XLXC::LXC, container_name)
  rootfs = File.join(container, "rootfs")
  config = File.join(container, "config")
  fstab = File.join(container, "fstab")

  # Set up container config file.
  open(config, 'w') { |f|
    f.puts(XLXC::LXC_CONFIG_TEMPLATE)
    f.puts("lxc.network.link=#{XLXC::DEF_BRIDGE_NAME}\n"        \
           "lxc.network.veth.pair=veth.#{i}#{name}\n"           \
           "lxc.rootfs=#{rootfs}\n"                             \
           "lxc.utsname=#{container_name}\n"                    \
           "lxc.mount=#{fstab}")
  }

  # Set up container fstab file.
  open(fstab, 'w') { |f|
    f.puts(XLXC::FSTAB_TEMPLATE)
  }

  # Set up container interfaces file (bypass DHCP).
  open(File.join(rootfs, XLXC::INTERFACES_FILE), 'w') { |f|
    f.puts(sprintf(XLXC::INTERFACES_TEMPLATE, i + 1))
  }

  # Set up container hosts files.
  open(File.join(rootfs, XLXC::HOSTS_FILE), 'w') { |f|
    f.puts(sprintf(XLXC::HOSTS_TEMPLATE, name + i.to_s()))
  }

  open(File.join(rootfs, XLXC::HOSTNAME_FILE), 'w') { |f|
    f.puts(name + i.to_s())
  }

end

# Perform bind mounts necessary to run container.
#
def do_bind_mounts(rootfs)
  # Bind mount (read-only) directories from host.
  bind_mount(XLXC::BIN, File.join(rootfs, XLXC::BIN), true, true)
  bind_mount(XLXC::LIB64, File.join(rootfs, XLXC::LIB64), true, true)
  bind_mount(XLXC::LIB, File.join(rootfs, XLXC::LIB), true, true)
  bind_mount(XLXC::SBIN, File.join(rootfs, XLXC::SBIN), true, true)
  bind_mount(XLXC::USR, File.join(rootfs, XLXC::USR), true, true)
end

# Create container filesystem by bind mounting from host.
#
def create_fs(rootfs)
  FileUtils.mkdir_p(rootfs)

  # Bind mount (read-only) directories from host.
  do_bind_mounts(rootfs)

  # Create dev directory and necessary files (pts, random, urandom).
  FileUtils.mkdir_p(File.join(rootfs, DEV_PTS))
  `mknod #{File.join(rootfs, DEV_RANDOM)} c 1 8`
  `mknod #{File.join(rootfs, DEV_URANDOM)} c 1 9`

  # Copy local etc to containers.
  `cp -R #{LOCAL_ETC} #{rootfs}`

  # Create necessary directories that are initially empty.
  FileUtils.mkdir_p(File.join(rootfs, PROC))
  FileUtils.mkdir_p(File.join(rootfs, SYS))
  FileUtils.mkdir_p(File.join(rootfs, HOME))
  FileUtils.mkdir_p(File.join(rootfs, ROOT))
  FileUtils.mkdir_p(File.join(rootfs, VAR_RUN))

  `chroot #{rootfs} passwd -d root`
end

# Creates and installs a script into each container.
#
def create_script(container_name)
  script = File.join(XLXC::LXC, container_name, "rootfs", "run.sh")
  open(script, 'w') { |f|
    f.puts("# Add HID for this container.")
    if !File.file?(File.join(XIA_HIDS, container_name))
      f.puts("sudo xip hid new #{container_name}")
    end
    f.puts("sudo xip hid add #{container_name}")
    f.puts("# Keep container running.")
    f.puts("cat")
  }
  `chmod +x #{script}`
end

# Configure the ethernet bridge to a container.
#
def config_bridge(bridge, gw)
  `brctl addbr #{bridge}`
  `brctl setfd #{bridge} 0`
  `ifconfig #{bridge} #{XLXC::DEF_PRIVATE_GW} \
   netmask #{XLXC::DEF_PRIVATE_NETMASK} promisc up`
  `iptables -t nat -A POSTROUTING -o #{gw} -j MASQUERADE`
  `echo 1 > /proc/sys/net/ipv4/ip_forward`
end

# Create or reset containers and ethernet bridges.
#
def setup_bridge_and_containers(name, first, last, gw, options)

  if options[:reset]
    `rm #{File.join(XLXC::BRIDGES, XLXC::DEF_BRIDGE_NAME)}`
  else
    `cp -R #{XIA} #{LOCAL_ETC}`
  end

  # Add ethernet bridge for these containers, if necessary.
  config_bridge(XLXC::DEF_BRIDGE_NAME, gw)

  for i in first..last
    container_name = name + i.to_s()

    if options[:reset]
      do_bind_mounts(File.join(XLXC::LXC, container_name, "rootfs"))
    else
      # Create filesystem for container.
      create_fs(File.join(XLXC::LXC, container_name, "rootfs"))

      # Configure the container.
      config_lxc(name, i)

      if options[:script]
        create_script(container_name)
      end

      `rm -rf #{File.join(LOCAL_ETC, "xia")}`
    end

    XLXC.inc_bridge_ref(XLXC::DEF_BRIDGE_NAME)
  end
end

if __FILE__ == $PROGRAM_NAME
  name = ARGV[0]
  first = ARGV[1].to_i()
  last = ARGV[2].to_i()
  gw = ARGV[3]

  options = parse_opts()
  check_for_errors(name, first, last, gw, options)
  setup_bridge_and_containers(name, first, last, gw, options)
end
