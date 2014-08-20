#
# xlxc-start: start a Linux XIA container
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script resets all containers and bridges that have been created
# by re-doing any bind mounts and re-initializing Ethernet bridges. This is
# particularly useful after the host has been rebooted.
#

 
require 'optparse'
require './xlxc'
require './xlxc-bridge'


USAGE = "Usage: ruby xlxc-start.rb -n name"

# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = USAGE

    options[:name] = nil
    opts.on('-n', '--name ARG', 'Container name') do |name|
      options[:name] = name
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
    puts("xlxc-start.rb must be run as root.")
    exit
  end

  # Check that there are no conflicts with the container name.
  name = options[:name]

  if name == nil
    puts("Specify name for container using -n or --name.")
    exit
  end
end

# Re-add the bridge to the list of interfaces by recreating it.
#
def recreate_bridge(container_bridge, name)
  cont_dir = File.join(XLXC_BRIDGE::BRIDGES, container_bridge, "containers")

  # Bridge is not present; we must create it and assign this container to it.
  iface = nil
  open(File.join(XLXC_BRIDGE::BRIDGES, container_bridge, "iface"), 'r') { |f|
    iface = f.readline().strip()
  }

  cidr = nil
  open(File.join(XLXC_BRIDGE::BRIDGES, container_bridge, "cidr"), 'r') { |f|
    cidr = f.readline().strip()
  }

  addr = nil
  open(File.join(cont_dir, name), 'r') { |f|
    addr = f.readline().strip()
  }

  `ruby xlxc-bridge.rb -n #{container_bridge} --del --force`
  `ruby xlxc-bridge.rb -n #{container_bridge} --add --gw #{iface} --ip #{cidr}`
  `echo #{addr} > #{File.join(cont_dir, name)}`
  XLXC_BRIDGE.inc_bridge_refcnt(container_bridge)
end

# Reset all Ethernet bridges.
#
def create_bridge_if_needed(name)
  # Get name of the bridge for this container.
  container_bridge = nil
  open(File.join(XLXC::LXC, name, "bridge"), 'r') { |f|
    container_bridge = f.readline().strip()
  }

  interfaces = Dir.entries(XLXC_BRIDGE::INTERFACES)
  if !interfaces.include?(container_bridge)
    recreate_bridge(container_bridge, name)
    return
  end

  cont_dir = File.join(XLXC_BRIDGE::BRIDGES, container_bridge, "containers")
  containers = Dir.entries(cont_dir)

  # Look to see if this bridge is already up.
  bridges = Dir.entries(XLXC_BRIDGE::BRIDGES)
  for bridge in bridges
    if bridge == container_bridge
      # Look to see if this bridge has recognized this container as a user.
      for container in containers
        # Bridge is present and knows about this container.
        return if container == name
      end

      cidr = nil
      open(File.join(XLXC_BRIDGE::BRIDGES, bridge, "cidr"), 'r') { |f|
        cidr = NetAddr::CIDR.create(f.readline().strip())
      }

      # Bridge is present but doesn't know about this container.
      addr = XLXC_BRIDGE.get_ip_addr(name, bridge, cidr)
 
      gateway = cidr.nth(1)
      broadcast = cidr.last()
      network = cidr.network()
      netmask = IPAddr.new('255.255.255.255').mask(cidr.bits()).to_s()
      rootfs = File.join(XLXC::LXC, name, "rootfs")

      open(File.join(rootfs, XLXC::INTERFACES_FILE), 'w') { |f|
        f.puts(sprintf(XLXC::INTERFACES_TEMPLATE, addr, netmask, network,
          broadcast, gateway))
      }

      `echo #{addr} > #{File.join(cont_dir, name)}`
      XLXC_BRIDGE.inc_bridge_refcnt(bridge)
      return
    end
  end
end

# Perform bind mounts necessary to run container.
#
def bind_mount_if_needed(name)
  rootfs = File.join(XLXC::LXC, name, "rootfs")

  # Bind mount (read-only) directories from host.
  for dir in XLXC::BIND_MOUNTED_DIRECTORIES
    if !Dir.exists?(File.join(rootfs, dir)) ||
       Dir.entries(File.join(rootfs, dir)).size() <= 2
      XLXC.bind_mount(dir, File.join(rootfs, dir), true, true)
    end
  end
end

# Check to make sure that the container is set-up correctly and
# then start the container.
#
def start_container(options)
  name = options[:name]
  create_bridge_if_needed(name)
  bind_mount_if_needed(name)
  `lxc-start -n #{name}`
end

if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  start_container(options)
end
