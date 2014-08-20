#
# xlxc-net: create a Linux XIA container network
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script batches the creation of Linux XIA containers
# so that more intricate networks can be quickly created.
#

 
require 'optparse'
require './xlxc'
require './xlxc-bridge'


USAGE = "Usage: ruby xlxc-net.rb -n name -s size -t topology -i iface"

# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = USAGE

    options[:iface] = nil
    opts.on('-i', '--iface ARG', 'Host gateway interface') do |iface|
      options[:iface] = iface
    end

    options[:name] = nil
    opts.on('-n', '--name ARG', 'Network naming scheme') do |name|
      options[:name] = name
    end

    options[:size] = 0
    opts.on('-s', '--size ARG', 'Size of network') do |size|
      options[:size] = size.to_i()
    end

    options[:topology] = nil
    opts.on('-t', '--topology ARG', 'Topology of network') do |top|
      options[:topology] = top
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
    puts("xlxc-net.rb must be run as root.")
    exit
  end

  size = options[:size]
  if size <= 0
    puts("The size of the network must be greater than zero.")
    exit
  end

  # Check that there are no conflicts with the container name.
  name = options[:name]
  if name == nil
    puts("Specify name for container using -n or --name.")
    exit
  end

  for i in 0..(size - 1)
    if File.exists?(File.join(XLXC::LXC, name + i.to_s()))
      puts("Container #{name + i.to_s()} already exists.")
      exit
    end
  end

  # Check that topology is valid.
  topology = options[:topology]
  if topology != "star" and topology != "connected"
    puts("Must indicate topology with either \"star\" or \"connected\".")
    exit
  end

  # We will use the naming scheme for the bridge, so make sure
  # there are no conflicts there.
  if topology == "connected"
    if Dir.entries(XLXC_BRIDGE::BRIDGES).include?(name + "br") ||
       Dir.entries(XLXC_BRIDGE::INTERFACES).include?(name + "br")
      puts("Bridge #{name + "br"} is already in use, so this\n" \
           "naming scheme cannot be used.")
      exit
    end
  else
    for i in 0..(size - 1)
      if Dir.entries(XLXC_BRIDGE::BRIDGES).include?(name + i.to_s() + "br") ||
         Dir.entries(XLXC_BRIDGE::INTERFACES).include?(name + i.to_s() + "br")
        puts("Bridge #{name + i.to_s() + "br"} is already in use, so this\n"
             "naming scheme cannot be used.")
        exit
      end
    end
  end

  iface = options[:iface]
  if iface == nil
    puts("Specify host's gateway interface.")
    exit
  end
end

# Returns a unique CIDR address large enough to contain @size
# IP addresses.
#
def get_cidr_big_enough(size)
  return "192.168.100.0/24"
end

# Creates a connected network of Linux XIA containrs, where each
# container is on the same Ethernet bridge.
#
def create_connected_network(name, size, iface)
  bridge = name + "br"
  cidr = get_cidr_big_enough(size)
  `ruby xlxc-bridge.rb -b #{bridge} --add --gw #{iface} --ip #{cidr}`
  for i in 0..(size - 1)
    `ruby xlxc-create.rb -n #{name + i.to_s()} -b #{bridge}`
  end
end

# Creates a star network of Linux XIA containers, where each
# container is on a separate Ethernet bridge.
#
def create_star_network(name, size, iface)
  for i in 0..(size - 1)
    bridge = name + i.to_s() + "br"
    cidr = get_cidr_big_enough(10)
    `ruby xlxc-bridge.rb -b #{bridge} --add --gw #{iface} --ip #{cidr}`
    `ruby xlxc-create.rb -n #{name + i.to_s()} -b #{bridge}`
  end
end

if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  name = options[:name]
  iface = options[:iface]
  size = options[:size]
  topology = options[:topology]
  if topology == "connected"
    create_connected_network(name, size, iface)
  elsif topology == "star"
    create_star_network(name, size, iface)
  else
    raise("No option chosen.")
  end
end
