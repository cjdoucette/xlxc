#
# xlxc-create: create Linux XIA containers
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script creates and initializes a Linux XIA container.
#

 
require 'fileutils'
require 'optparse'
require 'rubygems'
require 'netaddr'
require 'ipaddr'
require './xlxc'
require './xlxc-bridge'

class ContainerCreate
  # Directories that need to be directly copied.
  LOCAL_ETC = "./etc"

  # Directories that are initially empty, but need to be created.
  INITIALLY_EMPTY_DIRECTORIES = [
    "/proc",
    "/sys",
    "/dev/pts",
    "/dev/shm",
    "/home/ubuntu",
    "/root",
    "/var/run"
  ]

  # Character special files that need to be created.
  DEV_RANDOM   = "/dev/random"    # for HID principal in XIA
  DEV_URANDOM  = "/dev/urandom"   # for HID principal in XIA

  # Directories that hold XIA-related data.
  XIA       = "/etc/xia"
  XIA_HIDS  = File.join(XIA, "hid/prv")

  USAGE = "\nUsage: ruby xlxc-create.rb [options]\n\n"

  # Parse the command and organize the options.
  #
  def self.parse_opts()
    options = {}

    optparse = OptionParser.new do |opts|
      opts.banner = USAGE

      

      options[:name] = nil
      opts.on('-n', '--name ARG', 'Container name') do |name|
        options[:name] = name
      end

      options[:script] = false
      opts.on('-s', '--script', 'Create a script for this container') do
        options[:script] = true
      end
    end

    optparse.parse!
    return options
  end

  # Perform error checks on the parameters of the script and options
  #
  def self.check_for_errors(options)
    # Check that user is root.
    if Process.uid != 0
      puts("xlxc-create.rb must be run as root.")
      exit
    end

    # Check that user is running XIA kernel.
    # TODO Find a better way to check this.
    if !`uname -r`.include?("xia")
      puts("Must be running Linux XIA to create XIA containers.")
      exit
    end

    # Check that there are no conflicts with the container name.
    name = options[:name]

    if name == nil
      puts("Specify name for container using -n or --name.")
      exit
    end

    container = File.join(XLXC::LXC, name)
    if options[:reset] && !File.exist?(container)
      puts("Container #{container} does not exist.")
      exit
    end

    if !options[:reset] && File.exist?(container)
      puts("Container #{container} already exists in #{XLXC::LXC}.")
      exit
    end
    
  end

  # Create container filesystem by bind mounting from host.
  #
  def self.create_fs(rootfs)
    FileUtils.mkdir_p(rootfs)

    # Bind mount (read-only) directories from host.
    for dir in XLXC::BIND_MOUNTED_DIRECTORIES
      XLXC.bind_mount(dir, File.join(rootfs, dir), true, true)
    end

    # Copy local etc to containers.
    `cp -R #{LOCAL_ETC} #{rootfs}`

    # Create necessary directories that are initially empty.
    for dir in INITIALLY_EMPTY_DIRECTORIES
      FileUtils.mkdir_p(File.join(rootfs, dir))
    end

    # Create dev directory and necessary files (pts, random, urandom).
    `mknod #{File.join(rootfs, DEV_RANDOM)} c 1 8`
    `mknod #{File.join(rootfs, DEV_URANDOM)} c 1 9`

    # Remove root password.
    `chroot #{rootfs} passwd -d root`
  end

  # Creates and installs a script into each container.
  #
  def self.create_script(container_name)
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

  # Copy a default LXC configuration file and add configuration
  # information for it that is specific to this container, such
  # as a network interface, hardware address, and bind mounts.
  #
  def self.config_container(name, bridge)
    container = File.join(XLXC::LXC, name)
    rootfs = File.join(container, "rootfs")
    config = File.join(container, "config")
    fstab = File.join(container, "fstab")
    bridge_file = File.join(container, "bridge")

    # Set up container config file.
    open(config, 'w') { |f|
      f.puts(XLXC::LXC_CONFIG_TEMPLATE)
      f.puts("lxc.network.link=#{bridge}\n"                       \
             "lxc.network.veth.pair=#{name}veth\n"                \
             "lxc.rootfs=#{rootfs}\n"                             \
             "lxc.utsname=#{name}\n"                              \
             "lxc.mount=#{fstab}")
    }

    # Set up container fstab file.
    open(fstab, 'w') { |f|
      f.puts(XLXC::FSTAB_TEMPLATE)
    }

    # Set up container hosts files.
    open(File.join(rootfs, XLXC::HOSTS_FILE), 'w') { |f|
      f.puts(sprintf(XLXC::HOSTS_TEMPLATE, name))
    }

    open(File.join(rootfs, XLXC::HOSTNAME_FILE), 'w') { |f|
      f.puts(name)
    }

    open(bridge_file, 'w') { |f|
      f.puts(bridge)
    }
  end

  # Setup a container with the given options.
  #
  def self.setup_container(options)
    name = options[:name]
    #bridge = options[:bridge]

    `cp -R #{XIA} #{LOCAL_ETC}`

    # Create filesystem for container.
    create_fs(File.join(XLXC::LXC, name, "rootfs"))

    # Configure the container (network, fstab, hostname).
    #config_container(name, bridge)

    if options[:script]
      create_script(name)
    end

    `rm -rf #{File.join(LOCAL_ETC, "xia")}`
  end

  if __FILE__ == $PROGRAM_NAME
    options = parse_opts()
    check_for_errors(options)
    setup_container(options)
  end

end