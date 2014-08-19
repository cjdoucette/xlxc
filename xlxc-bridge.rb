#
# xlxc-bridge: create Ethernet bridges for Linux XIA containers
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script creates and initializes an Ethernet bridge for use
# with Linux XIA containers (XLXC).
#

 
require 'fileutils'
require 'optparse'
require 'rubygems'
require 'netaddr'
require 'ipaddr'

class XLXC_BRIDGE

  # Directory that contains directories for interfaces.
  INTERFACES = "/sys/class/net"

  # Directory that contains bridge information.
  BRIDGES = File.join(Dir.pwd(), "bridges")

  USAGE =
  "\nUsage:"                                                                  \
    "\truby xlxc-bridge.rb -n name --add --gw host-gw-iface --ip bridge-cidr" \
    "\n\tOR\n"                                                                \
    "\truby xlxc-bridge.rb -n name --del [--force]\n\n"

  # Parse the command and organize the options.
  #
  def self.parse_opts()
    options = {}

    optparse = OptionParser.new do |opts|
      opts.banner = USAGE

      options[:add] = false
      opts.on('-a', '--add', 'Add a bridge') do
        options[:add] = true
      end

      options[:delete] = false
      opts.on('-d', '--del', 'Delete a bridge') do
        options[:delete] = true
      end

      options[:force] = false
      opts.on('-f', '--force', 'Force a bridge to be deleted') do
        options[:force] = true
      end

      options[:gw] = nil
      opts.on('-g', '--gw ARG', 'Gateway interface on host') do |gw|
        options[:gw] = gw
      end

      options[:ip] = nil
      opts.on('-i', '--ip ARG', 'Bridge IPv4 address in CIDR notation') do |ip|
        options[:ip] = ip
      end

      options[:name] = nil
      opts.on('-n', '--name ARG', 'Bridge name') do |name|
        options[:name] = name
      end
    end

    optparse.parse!
    return options
  end

  # Check for errors when trying to add or delete an Ethernet bridge.
  #
  def self.check_for_errors(options)
    # Check that user is root.
    if Process.uid != 0
      puts("xlxc-bridge.rb must be run as root.")
      exit
    end

    name = options[:name]
    if name == nil
      puts("Specify name for bridge.")
      exit
    end

    gateway = options[:gw]
    if options[:add] and (options[:gw] == nil or options[:ip] == nil)
      puts("Specify host gateway interface and IPv4 address\n" \
           "of the bridge using CIDR notation.")
      exit
    end

    # Check to make sure gateway interface exists, if adding.
    if options[:add] and !File.exists?(File.join(INTERFACES, gateway))
      puts("Host interface #{gateway} does not exist.")
      exit
    end

    # Check to make sure bridge exists, if deleting.
    if options[:delete] and !File.exists?(File.join(BRIDGES, name))
      puts("Cannot delete bridge #{name} because it does not exist.")
      exit
    end

    if options[:add] and options[:delete]
      puts("Cannot add and delete a bridge simultaneously.")
      exit
    end

    if !options[:add] and !options[:delete]
      puts("Must specify --add or --delete.")
      exit
    end

    if options[:add] and options[:force]
      puts("--force has no effect when specified with --add.")
      exit
    end
  end

  # Increment the reference count to this bridge.
  #
  def self.inc_bridge_refcnt(name)
    bridge_dir = File.join(BRIDGES, name)
    if !File.exists?(bridge_dir)
      return
    end

    bridge_refcnt_file = File.join(bridge_dir, "refcnt")
    open(bridge_refcnt_file, 'r') { |f|
      f.flock(File::LOCK_EX)
      count = f.readline.to_i()
      `echo #{count + 1} > #{bridge_refcnt_file}`
      f.close()
    }
  end

  # Delete a bridge by removing it from the list
  # of interfaces and removing any configuration
  # information.
  #
  def self.__delete_bridge(name)
    `ifconfig #{name} promisc down`
    `brctl delbr #{name}`
    `rm -r #{File.join(BRIDGES, name)}`
  end

  # Decrement the reference count to this bridge,
  # destroying it if necessary.
  #
  def self.dec_bridge_refcnt(name)
    bridge_dir = File.join(BRIDGES, name)
    if !File.exists?(bridge_dir)
      return
    end

    bridge_refcnt_file = File.join(bridge_dir, "refcnt")
    open(bridge_refcnt_file, 'r') { |f|
      f.flock(File::LOCK_EX)
      count = f.readline.to_i()
      if count > 0
        `echo #{count - 1} > #{bridge_refcnt_file}`
      end
      f.close()
    }
  end

  # Add an Ethernet bridge, if it does not already exist.
  #
  def self.add_bridge(options)
    name = options[:name]
    gw = options[:gw]

    cidr = NetAddr::CIDR.create(options[:ip])
    addr = cidr.ip()
    netmask = IPAddr.new('255.255.255.255').mask(cidr.bits()).to_s()

    `brctl addbr #{name}`
    `brctl setfd #{name} 0`
    `ifconfig #{name} #{addr} netmask #{netmask} promisc up`
    `iptables -t nat -A POSTROUTING -o #{gw} -j MASQUERADE`
    `echo 1 > /proc/sys/net/ipv4/ip_forward`

    `mkdir -p #{File.join(BRIDGES, name)}`
    `echo 0 > #{File.join(BRIDGES, name, "refcnt")}`
    `echo #{cidr.to_s()} > #{File.join(BRIDGES, name, "cidr")}`
    `mkdir #{File.join(BRIDGES, name, "containers")}`
  end

  # Delete an Ethernet bridge, if no containers are using it.
  #
  def self.delete_bridge(options)
    name = options[:name]
    force = options[:force]

    bridge_dir = File.join(BRIDGES, name)
    refcnt = -1
    open(File.join(bridge_dir, "refcnt"), 'r') { |f|
      refcnt = f.readline.to_i()
    }

    if !force and refcnt != 0
      puts("At least one container is using this bridge.\n"  \
           "Use --force to delete the bridge, potentially\n"   \
           "corrupting the networks for the containers that\n" \
           "use this bridge:")
      Dir.foreach(File.join(BRIDGES, name, "containers")) do |item|
        next if item == '.' or item == '..'
        puts("\t" + item)
      end
      return
    end

    __delete_bridge(name)
  end

  if __FILE__ == $PROGRAM_NAME
    options = parse_opts()
    check_for_errors(options)
    if options[:add]
      add_bridge(options)
    elsif options[:delete]
      delete_bridge(options)
    else
      raise("No option chosen.")
    end
  end

end
