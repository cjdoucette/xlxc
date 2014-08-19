#
# xlxc-reset: reset all Linux XIA containers and bridges
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


USAGE = "Usage: ruby xlxc-reset.rb"

# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = USAGE
  end

  optparse.parse!
  return options
end

# Perform error checks on the parameters of the script and options
#
def check_for_errors(options)
  # Check that user is root.
  if Process.uid != 0
    puts("xlxc-reset.rb must be run as root.")
    exit
  end
end

# Reset all Ethernet bridges.
#
def init_bridges(options)
  bridges = Dir.entries(XLXC_BRIDGE::BRIDGES)
  for bridge in bridges
    next if bridge == '.' or bridge == '..'

    iface = nil
    open(File.join(XLXC_BRIDGE::BRIDGES, bridge, "iface"), 'r') { |f|
      iface = f.readline().strip()
    }

    cidr = nil
    open(File.join(XLXC_BRIDGE::BRIDGES, bridge, "cidr"), 'r') { |f|
      cidr = f.readline().strip()
    }

    `ruby xlxc-bridge.rb -n #{bridge} --del --force`
    `ruby xlxc-bridge.rb -n #{bridge} --add --gw #{iface} --ip #{cidr}`
  end
end

# Reset all containers by re-bind mounting.
#
def reset_container(options)
  containers = Dir.entries(XLXC::LXC)
  for container in containers
    next if container == '.' or container == '..'

    bridge = nil
    open(File.join(XLXC::LXC, container, "bridge"), 'r') { |f|
      bridge = f.readline().strip()
    }

    `ruby xlxc-destroy.rb -n #{container}`
    `ruby xlxc-create.rb -n #{container} -b #{bridge}`
  end

end

if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  init_bridges(options)
  reset_container(options)
end
