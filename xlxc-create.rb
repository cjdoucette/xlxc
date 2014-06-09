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


# Directories that need to be directly copied (etc) or
# bind mounted (read-write) (dev) from the host.
LOCAL_ETC = "./etc"
LOCAL_DEV = "./dev"
DEV_PTS   = File.join(LOCAL_DEV, "pts")

# Directories that are initially empty, but need to be created.
PROC      = "/proc"
SYS       = "/sys"

# Directories that hold XIA-related data.
XIA       = "/etc/xia"
XIA_HIDS  = File.join(XIA, "hid/prv")


# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: ruby xlxc-create.rb [OPTIONS]"

    options[:num] = 1
    opts.on('-c', '--count=COUNT', 'Set number of containers') do |count|
      options[:num] = count.to_i()
    end

    options[:ip] = false
    opts.on('-i', '--ip', 'Create containers with IP stack only') do |name|
      options[:ip] = true
    end

    options[:script] = false
    opts.on('-s', '--script', 'Create a script for each container') do |name|
      options[:script] = true
    end
  end

  optparse.parse!
  return options
end

# Perform error checks on the parameters of the script and options
#
def check_for_errors(options)
  # Check that user is root.
  if Process.uid != 0
    puts("xlxc-create must be run as root.")
    exit
  end

  # Check that user is running XIA kernel.
  # TODO Find a better way to check this.
  if !options[:ip] && !`uname -r`.include?("xia")
    puts("Must be running Linux XIA to create XIA containers.")
    exit
  end

  # Check that there are no conflicts in container names.
  for i in 1..options[:num]
    container = File.join(XLXC::LXC, options[:ip] ? "ip" : "xia" + i.to_s())
    if File.exist?(container)
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
def config_lxc(name, i, stack)
  container = File.join(XLXC::LXC, name)
  rootfs = File.join(container, "rootfs")
  config = File.join(container, "config")
  fstab = File.join(container, "fstab")

  # Set up container config file.
  open(config, 'w') { |f|
    f.puts(XLXC::LXC_CONFIG_TEMPLATE)
    f.puts("lxc.network.link=#{name}br\n"                       \
           "lxc.network.veth.pair=veth.#{i}#{stack}\n"          \
           "lxc.rootfs=#{rootfs}\n"                             \
           "lxc.utsname=#{name}\n"                              \
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
end

# Create container filesystem by bind mounting from host.
#
def create_fs(rootfs)
  FileUtils.mkdir_p(rootfs)

  # Bind mount (read-only) directories from host.
  bind_mount(XLXC::BIN, File.join(rootfs, XLXC::BIN), true, true)
  bind_mount(XLXC::LIB64, File.join(rootfs, XLXC::LIB64), true, true)
  bind_mount(XLXC::VAR, File.join(rootfs, XLXC::VAR), true, true)
  bind_mount(XLXC::LIB, File.join(rootfs, XLXC::LIB), true, true)
  bind_mount(XLXC::SBIN, File.join(rootfs, XLXC::SBIN), true, true)
  bind_mount(XLXC::USR, File.join(rootfs, XLXC::USR), true, true)

  # Bind mount (read-write) local dev to containers.
  bind_mount(LOCAL_DEV, File.join(rootfs, XLXC::SYSTEM_DEV), true, false)
  # Copy local etc to containers.
  `cp -R #{LOCAL_ETC} #{rootfs}`

  # Create necessary directories that are initially empty.
  FileUtils.mkdir_p(File.join(rootfs, PROC))
  FileUtils.mkdir_p(File.join(rootfs, SYS))
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
  
# Create Linux XIA containers with the given options by
# installing and configuring Ubuntu.
#
def create_containers(options)
  num_containers = options[:num]
  stack_name = options[:ip] ? "ip" : "xia"

  # Set up local etc and dev directories.
  if stack_name == "xia" 
    `cp -R #{XIA} #{LOCAL_ETC}`
  end
  `rm -rf #{LOCAL_DEV}`
  `cp -R #{XLXC::SYSTEM_DEV} #{LOCAL_DEV}`
  `rm -rf #{File.join(DEV_PTS, "*")}`

  for i in 1..num_containers
    container_name = stack_name + i.to_s()

    # Create filesystem for container.
    create_fs(File.join(XLXC::LXC, container_name, "rootfs"))

    # Add ethernet bridge to this container.
    `brctl addbr #{container_name}br`
    `ifconfig #{container_name}br hw ether 00:00:00:00:00:#{"%02x" % i}`
    `ifconfig #{container_name}br promisc up`

    # Configure the container.
    config_lxc(container_name, i, stack_name)

    if options[:script]
      create_script(container_name)
    end
  end

  if stack_name == "xia"
    `rm -rf #{File.join(LOCAL_ETC, "xia")}`
  end
end


if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  create_containers(options)
end
