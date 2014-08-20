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

# Set up the network for this bridge. This involves re-creating the
# Ethernet bridge (if necessary) and allocating an IP address.
#
def setup_net(name)
  bridge = XLXC_BRIDGE.get_bridge(name)
  cidr = XLXC_BRIDGE.get_bridge_cidr(bridge)
  iface = XLXC_BRIDGE.get_bridge_iface(bridge)

  # If this interface is not up, create it.
  interfaces = Dir.entries(XLXC_BRIDGE::INTERFACES)
  if !interfaces.include?(bridge)
    XLXC_BRIDGE.add_interface(bridge, cidr, gateway_iface)
  end

  XLXC_BRIDGE.alloc_ip_address_from_bridge(name, bridge)
end

# Perform bind mounts necessary to run container.
#
def setup_fs(name)
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
  setup_net(name)
  setup_fs(name)
  `lxc-start -n #{name}`
end

if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  start_container(options)
end
