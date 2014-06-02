#!/usr/bin/ruby -w

#
# xlxc-create: create XIA-linux containers
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script creates and initializes a given number of IP or XIA linux
# containers. Each container uses a separate network bridge to the host,
# and by default creates containers running Ubuntu Saucy Salamander (13.10).
#
# This script is based on the lxc-create and lxc-ubuntu scripts written by:
#     Daniel Lezcano <daniel.lezcano@free.fr>     (lxc-create)
#     Serge Hallyn   <serge.hallyn@canonical.com> (lxc-ubuntu)
#     Wilhelm Meier  <wilhelm.meier@fh-kl.de>     (lxc-ubuntu)
#

 
require 'fileutils'
require 'optparse'
require './xlxc'


# Ubuntu information.
ARCH    = "amd64"
RELEASE = "saucy"
MIRROR  = "http://archive.ubuntu.com/ubuntu"

# Paths for LXC containers and distribution caches.
LXC_CACHE        = File.join("/var/cache/lxc", RELEASE)
LXC_CACHE_DL     = File.join(LXC_CACHE, "partial-" + ARCH)
LXC_CACHE_ROOTFS = File.join(LXC_CACHE, "rootfs-" + ARCH)

# Paths for container files.
CONTAINER_INTERFACES = "/etc/network/interfaces"
CONTAINER_HOSTS = "/etc/hosts"


# Bind mount a source file to a destination file.
#
def bind_mount(src, dst, isDir)
  if isDir
    `mkdir -p #{dst}`
  else
    FileUtils.touch(dst)
  end
  `mount --bind #{src} #{dst}`
end

# Bind mount LXC to a container.
#
def get_lxc(rootfs)
  FileUtils.mkdir_p(File.join(rootfs, XLXC::LXC_DIR))

  XLXC::LXC_FILES.each do |f|
    bind_mount(f, File.join(rootfs, f), false)
  end
end

# Flush the distribution cache and any partial download that
# may be present.
#
def flush()
  FileUtils.rm_rf(LXC_CACHE_DL)
  FileUtils.rm_rf(LXC_CACHE_ROOTFS)
end

# Download an Ubuntu distribution using debootstrap.
#
def download_ubuntu()
  print("Downloading Ubuntu #{RELEASE}... ")
  `debootstrap --arch #{ARCH} #{RELEASE} #{LXC_CACHE_DL} #{MIRROR}`
  if !$?.success?
    puts("failed.")
    flush()
    exit
  end
  puts("done.")

  FileUtils.mv(LXC_CACHE_DL, LXC_CACHE_ROOTFS)
end

# Install an Ubuntu container by copying the rootfs from the cache.
#
def install_ubuntu(container)
  if !File.exist?(LXC_CACHE)
    `mkdir -p #{LXC_CACHE}`
  end

  if !File.exist?(LXC_CACHE_ROOTFS)
    flush()
    download_ubuntu()
  end

  # Copy downloaded distribution to container and rename rootfs.
  `cp -R #{LXC_CACHE_ROOTFS} #{container}`
  FileUtils.mv(File.join(container, "rootfs-" + ARCH),
               File.join(container, "rootfs"))
end

# Configure an Ubuntu container by setting up the network interfaces,
# hosts identifiers, software, and user information.
#
def configure_ubuntu(name)
  rootfs = File.join(XLXC::LXC, name, "rootfs")

  # Configure network interfaces.
  open(File.join(rootfs, CONTAINER_INTERFACES), 'w') { |f|
    f.puts(XLXC::INTERFACES)
  }

  # Set the minimal hosts.
  open(File.join(rootfs, CONTAINER_HOSTS), 'a') { |f|
    f.puts("127.0.0.0   localhost\n" \
           "127.0.1.1   #{name}")
  }

  `chroot #{rootfs} locale-gen en_US en_US.UTF-8`

  # Create a user with a home directory with username ubuntu.
  `chroot #{rootfs} useradd --create-home -s /bin/bash ubuntu`
  # Change username:password to ubuntu:ubuntu.
  `echo "ubuntu:ubuntu" | chroot #{rootfs} chpasswd`
  # Add user to sudo group.
  `chroot #{rootfs} adduser ubuntu sudo`
end

# Copy a default LXC configuration file and add configuration
# information for it that is specific to this container, such
# as a network interface, hardware address, and bind mounts.
#
def copy_configuration(name, bridge, i, stack)
  container = File.join(XLXC::LXC, name)
  rootfs = File.join(container, "rootfs")
  config = File.join(container, "config")
  fstab = File.join(container, "fstab")

  unique_byte = "%02x" % i

  # Set up container config file.
  open(config, 'w') { |f|
    f.puts(XLXC::LXC_CONFIG)
    f.puts("lxc.network.link=#{bridge}\n"                       \
           "lxc.network.hwaddr=00:16:3e:93:f7:#{unique_byte}\n" \
           "lxc.network.veth.pair=veth.#{i}#{stack}\n"          \
           "lxc.rootfs=#{rootfs}\n"                             \
           "lxc.utsname=#{name}\n"                              \
           "lxc.mount=#{fstab}\n"                               \
           "lxc.arch=#{ARCH}")
  }

  # Set up container fstab file.
  open(fstab, 'w') { |f|
    f.puts(XLXC::FSTAB)
  }

  # Set up bind mounts.
  if stack == "xia"
    bind_mount(XLXC::MODULES, File.join(rootfs, XLXC::MODULES), true)
    bind_mount(XLXC::XIP, File.join(rootfs, XLXC::XIP), false)
    bind_mount(XLXC::LIBXIA, File.join(rootfs, XLXC::LIBXIA), false)
    bind_mount(XLXC::XIA_DATA, File.join(rootfs, XLXC::XIA_DATA), true)
  end

  get_lxc(rootfs)
end

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

    options[:flush] = false
    opts.on('-f', '--flush', 'Flush distribution cache') do
      options[:flush] = true
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

  # Ensure that user has debootstrap program.
  `which debootstrap`
  if !$?.success?
    puts("debootstrap program not found.")
    exit
  end
end

# Create Linux XIA containers with the given options by
# installing and configuring Ubuntu.
#
def create_containers(options)
  num = options[:num]
  stack_name = options[:ip] ? "ip" : "xia"

  for i in 1..num
    container_name = stack_name + i.to_s()
    container_path = File.join(XLXC::LXC, container_name)
    `mkdir -p #{container_path}`

    # Add ethernet bridge to this container.
    bridge = container_name + "br"
    `brctl addbr #{bridge}`
    `ifconfig #{bridge} promisc up`

    install_ubuntu(container_path)
    configure_ubuntu(container_name)
    copy_configuration(container_name, bridge, i, stack_name)
  end
end


if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)

  if options[:flush]
    flush()
  end

  create_containers(options)
end
