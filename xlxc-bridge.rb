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
require './xlxc'

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

  # Given the name of a container, fetch the bridge it uses.
  #
  def self.get_bridge(name)
    bridge = nil
    open(File.join(XLXC::LXC, name, "bridge"), 'r') { |f|
      bridge = f.readline().strip()
    }
    return bridge
  end

  # Get CIDR address of Ethernet bridge.
  #
  def self.get_bridge_cidr(bridge)
    cidr = nil
    open(File.join(XLXC_BRIDGE::BRIDGES, bridge, "cidr"), 'r') { |f|
      cidr = NetAddr::CIDR.create(f.readline().strip())
    }
    return cidr
  end

  # Get gateway interface of host for Ethernet bridge.
  #
  def self.get_bridge_iface(bridge)
    iface = nil
    open(File.join(XLXC_BRIDGE::BRIDGES, bridge, "iface"), 'r') { |f|
      iface = f.readline().strip()
    }
    return iface
  end

  # Find a free IP address for this bridge.
  # TODO: lock the bridge file.
  #
  def self.get_free_ip_address(name, bridge, cidr)
    # Skip network address and gateway address.
    potential_addresses = cidr.range(2)
    containers_dir = File.join(BRIDGES, bridge, "containers")
    containers = Dir.entries(containers_dir)

    for address_to_try in potential_addresses
      address_already_allocated = false

      for cont in containers
        next if cont == '.' or cont == '..'

        existing_ip_address = nil
        open(File.join(containers_dir, cont), 'r') { |f|
          existing_ip_address = f.readline().strip()
        }

        if address_to_try == existing_ip_address
          address_already_allocated = true
          break
        end
      end

      if !address_already_allocated
        return address_to_try
      end

    end

    # All addresses have been allocated.
    return nil
  end

  # Add the allocated IP address to the /etc/network/interfaces file
  # and document this address in the BRIDGES directory.
  #
  def self.add_ip_address_to_container(name, bridge, cidr, address)
    # Assume gateway address is at index 1 (second available address).
    gateway = cidr.nth(1)
    broadcast = cidr.last()
    network = cidr.network()
    netmask = IPAddr.new('255.255.255.255').mask(cidr.bits()).to_s()

    rootfs = File.join(XLXC::LXC, name, "rootfs")
    open(File.join(rootfs, XLXC::INTERFACES_FILE), 'w') { |f|
      f.puts(sprintf(XLXC::INTERFACES_TEMPLATE, address, netmask, network,
        broadcast, gateway))
    }

    `echo #{address} > #{File.join(BRIDGES, bridge, "containers", name)}`
  end

  # Find a free IP address for this bridge and add it to the container.
  #
  def self.alloc_ip_address_from_bridge(name, bridge)
    cidr = get_bridge_cidr(bridge)
    address = get_free_ip_address(name, bridge, cidr)
    add_ip_address_to_container(name, cidr, address)
  end

  # Add bridge interface using bridge-utils.
  #
  def self.add_interface(bridge, cidr, gateway_iface)
    gateway_address = cidr.nth(1)
    netmask = IPAddr.new('255.255.255.255').mask(cidr.bits()).to_s()

    `brctl addbr #{bridge}`
    `brctl setfd #{bridge} 0`
    `ifconfig #{bridge} #{gateway_address} netmask #{netmask} promisc up`
    `iptables -t nat -A POSTROUTING -o #{gateway_iface} -j MASQUERADE`
    `echo 1 > /proc/sys/net/ipv4/ip_forward`
  end

  # Add an Ethernet bridge, if it does not already exist.
  #
  def self.add_bridge(options)
    bridge = options[:name]
    gateway_iface = options[:gw]
    cidr = NetAddr::CIDR.create(options[:ip])

    add_interface(bridge, cidr, gateway_iface)

    `mkdir -p #{File.join(BRIDGES, bridge)}`
    `echo 0 > #{File.join(BRIDGES, bridge, "refcnt")}`
    `echo #{gateway_iface} > #{File.join(BRIDGES, bridge, "iface")}`
    `echo #{cidr.to_s()} > #{File.join(BRIDGES, bridge, "cidr")}`
    `mkdir #{File.join(BRIDGES, bridge, "containers")}`
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
        puts("  " + item)
      end
      return
    end

    `ifconfig #{name} promisc down`
    `brctl delbr #{name}`
    `rm -r #{File.join(BRIDGES, name)}`
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
