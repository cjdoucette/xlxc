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
  unique_byte = "%02x" % i
  open(config, 'w') { |f|
    f.puts(XLXC::LXC_CONFIG_TEMPLATE)
    f.puts("lxc.network.link=#{name}br\n"                       \
           "lxc.network.hwaddr=00:16:3e:93:f7:#{unique_byte}\n" \
           "lxc.network.veth.pair=veth.#{i}#{stack}\n"          \
           "lxc.rootfs=#{rootfs}\n"                             \
           "lxc.utsname=#{name}\n"                              \
           "lxc.mount=#{fstab}")
  }

  # Set up container fstab file.
  open(fstab, 'w') { |f|
    f.puts(XLXC::FSTAB_TEMPLATE)
  }

  # With this block commented-out, XIA containers are dual-stacked.
  #if stack_name == "ip"
    open(File.join(rootfs, XLXC::INTERFACES_FILE), 'w') { |f|
      f.puts(sprintf(XLXC::INTERFACES_TEMPLATE, i))
    }
  #end
end

# Create container filesystem by bind mounting from host.
#
def create_fs(rootfs)
  FileUtils.mkdir_p(rootfs)

  # Bind mount directories from host.
  bind_mount(XLXC::BIN, File.join(rootfs, XLXC::BIN), true, true)
  bind_mount(XLXC::LIB64, File.join(rootfs, XLXC::LIB64), true, true)
  bind_mount(XLXC::VAR, File.join(rootfs, XLXC::VAR), true, true)
  bind_mount(XLXC::LIB, File.join(rootfs, XLXC::LIB), true, true)
  bind_mount(XLXC::SBIN, File.join(rootfs, XLXC::SBIN), true, true)
  bind_mount(XLXC::USR, File.join(rootfs, XLXC::USR), true, true)

  # Bind mount (read-write) local dev to containers.
  bind_mount(XLXC::LOCAL_DEV, File.join(rootfs, XLXC::SYSTEM_DEV), true, false)

  # Copy local etc to containers.
  FileUtils.cp_r(XLXC::ETC, rootfs)

  # Create necessary directories that are initially empty.
  FileUtils.mkdir_p(File.join(rootfs, XLXC::PROC))
  FileUtils.mkdir_p(File.join(rootfs, XLXC::SYS))
end

# Create Linux XIA containers with the given options by
# installing and configuring Ubuntu.
#
def create_containers(options)
  num_containers = options[:num]
  stack_name = options[:ip] ? "ip" : "xia"

  if stack_name == "xia" 
    FileUtils.cp_r(XLXC::XIA, XLXC::ETC)
  end

  # Need to use cp -R here, as FileUtils.cp_r cannot handle
  # character special files.
  `cp -R #{XLXC::SYSTEM_DEV} #{ XLXC::LOCAL_DEV}`
  # Reset local dev/pts directory.
  `rm -rf #{File.join(XLXC::DEV_PTS, "*")}`

  for i in 1..num_containers
    container_name = stack_name + i.to_s()

    # Create filesystem for container.
    create_fs(File.join(XLXC::LXC, container_name, "rootfs"))

    # Add ethernet bridge to this container.
    `brctl addbr #{container_name}br`
    `ifconfig #{container_name}br promisc up`

    # Configure the container.
    config_lxc(container_name, i, stack_name)
  end

  if stack_name == "xia"
    FileUtils.rm_rf(File.join(XLXC::ETC, "xia"))
  end
end


if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  create_containers(options)
end