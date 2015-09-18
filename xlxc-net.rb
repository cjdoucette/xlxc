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


USAGE =
  "\nUsage:"                                                               \
  "\truby xlxc-net.rb -n name -s size --create -t topology [OPTIONS]"      \
  "\n\tOR\n"                                                               \
  "\truby xlxc-net.rb -n name -s size --destroy -t topology"               \
  "\n\tOR\n"                                                               \
  "\truby xlxc-net.rb -n name -s size --start"                             \
  "\n\tOR\n"                                                               \
  "\truby xlxc-net.rb -n name -s size --stop"                              \
  "\n\tOR\n"                                                               \
  "\truby xlxc-net.rb -n name -s size --execute -- command\n\n"            \

# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = USAGE

    options[:start] = false
    opts.on('-a', '--start', 'Start containers in this network') do
      options[:start] = true
    end

    options[:create] = false
    opts.on('-c', '--create', 'Create this container network') do
      options[:create] = true
    end

    options[:destroy] = false
    opts.on('-d', '--destroy', 'Destroy this container network') do
      options[:destroy] = true
    end

    options[:script] = false
    opts.on('-e', '--exec-script', 'Add executable script (--create)') do
      options[:script] = true
    end

    options[:iface] = nil
    opts.on('-i', '--iface ARG', 'Host gateway iface (--create)') do |iface|
      options[:iface] = iface
    end

    options[:name] = nil
    opts.on('-n', '--name ARG', 'Network naming scheme') do |name|
      options[:name] = name
    end

    options[:stop] = false
    opts.on('-o', '--stop', 'Stop containers in this network') do
      options[:stop] = true
    end

    options[:size] = 0
    opts.on('-s', '--size ARG', 'Size of network') do |size|
      options[:size] = size.to_i()
    end

    options[:topology] = nil
    opts.on('-t', '--topology ARG', 'Topology of network') do |top|
      options[:topology] = top
    end

    options[:exec] = nil
    opts.on('-x', '--execute -- ARG', 'Exec command in containers') do |cmd|
      options[:exec] = cmd
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

  name = options[:name]
  if name == nil
    puts("Specify name for container using -n or --name.")
    exit
  end

  size = options[:size]
  if size <= 0
    puts("The size of the network must be greater than zero.")
    exit
  end

  if size > 65534
    puts("The size of the network must be less than 65535.")
    exit
  end

  count = 0
  if options[:create]
    count += 1
  end
  if options[:destroy]
    count += 1
  end
  if options[:start]
    count += 1
  end
  if options[:stop]
    count += 1
  end
  if options[:exec] != nil
    count += 1
  end

  if count < 1 or count > 1
    puts("Must use one of: --create, --destroy, --start, --stop, --execute.")
    exit
  end

  # Check that topology is valid.
  topology = options[:topology]
  if (options[:create] or options[:destroy]) and 
     (topology != "star" and topology != "connected")
    puts("Must indicate topology with either \"star\" or \"connected\".")
    exit
  end

  # Check that there are no conflicts with the container name.
  if options[:create]
    for i in 0..(size - 1)
      if File.exists?(File.join(XLXC::LXC, name + i.to_s()))
        puts("Container #{name + i.to_s()} already exists.")
        exit
      end
    end

    # We will use the naming scheme for the bridge, so make sure
    # there are no conflicts there.
    if !Dir.exists?(XLXC_BRIDGE::BRIDGES)
      `mkdir -p #{XLXC_BRIDGE::BRIDGES}`
    end

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
          puts("Bridge #{name + i.to_s() + "br"} is already in use, so this\n" \
               "naming scheme cannot be used.")
          exit
        end
      end
    end
  end
end

# Creates a connected network of Linux XIA containrs, where each
# container is on the same Ethernet bridge.
#
def create_connected_network(name, size, iface, use_script)
  bridge = name + "br"
  cidr_str = XLXC_BRIDGE.get_free_cidr_block(size).to_s()
  if use_script
    `ruby xlxc-bridge.rb -b #{bridge} --iface #{iface} --cidr #{cidr_str}`
  else
    `ruby xlxc-bridge.rb -b #{bridge} --cidr #{cidr_str}`
  end
  for i in 0..(size - 1)
    if use_script
      `ruby xlxc-create.rb -n #{name + i.to_s()} -b #{bridge} --script`
    else
      `ruby xlxc-create.rb -n #{name + i.to_s()} -b #{bridge}`
    end
  end
end

# Creates a star network of Linux XIA containers, where each
# container is on a separate Ethernet bridge.
#
def create_star_network(name, size, iface, use_script)
  for i in 0..(size - 1)
    bridge = name + i.to_s() + "br"
    cidr_str = XLXC_BRIDGE.get_free_cidr_block(size).to_s()
    if use_script
      `ruby xlxc-bridge.rb -b #{bridge} --iface #{iface} --cidr #{cidr_str}`
      `ruby xlxc-create.rb -n #{name + i.to_s()} -b #{bridge} --script`
    else
      `ruby xlxc-bridge.rb -b #{bridge} --cidr #{cidr_str}`
      `ruby xlxc-create.rb -n #{name + i.to_s()} -b #{bridge}`
    end
  end
end

# Creates a tree network of Linux XIA containers, where each
# container is on a separate Ethernet bridge.

# Destroys a connected network of Linux XIA containrs, where each
# container is on the same Ethernet bridge.
#
def destroy_connected_network(name, size)
  bridge = name + "br"
  for i in 0..(size - 1)
    `ruby xlxc-destroy.rb -n #{name + i.to_s()}`
  end
  `ruby xlxc-bridge.rb -b #{bridge} --del`
end


# Destroys a star network of Linux XIA containers, where each
# container is on a separate Ethernet bridge.
#
def destroy_star_network(name, size)
  for i in 0..(size - 1)
    bridge = name + i.to_s() + "br"
    `ruby xlxc-destroy.rb -n #{name + i.to_s()}`
    `ruby xlxc-bridge.rb -b #{bridge} --del`
  end
end


# Starts a network of Linux XIA containers.
#
def start_network(name, size)
  for i in 0..(size - 1)
    `ruby xlxc-start.rb -n #{name + i.to_s()} --daemon`
  end
end

# Stops a network of Linux XIA containers.
#
def stop_network(name, size)
  for i in 0..(size - 1)
    `ruby xlxc-stop.rb -n #{name + i.to_s()}`
  end
end

# Executes a command on a network of Linux XIA containers.
#
def execute_network(name, size, command)
  for i in 0..(size - 1)
    `ruby xlxc-execute.rb -n #{name + i.to_s()} -- #{command}`
  end
end


if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)

  create = options[:create]
  destroy = options[:destroy]
  start = options[:start]
  stop = options[:stop]
  execute = options[:exec]

  name = options[:name]
  iface = options[:iface]
  size = options[:size]
  topology = options[:topology]
  script = options[:script]

  if create
    if topology == "connected"
      create_connected_network(name, size, iface, script)
    elsif topology == "star"
      create_star_network(name, size, iface, script)
    else
      raise("No option chosen.")
    end
  elsif destroy
    if topology == "connected"
      destroy_connected_network(name, size)
    elsif topology == "star"
      destroy_star_network(name, size)
    else
      raise("No option chosen.")
    end
  elsif start
    start_network(name, size)
  elsif stop
    stop_network(name, size)
  elsif execute != nil
    execute_network(name, size, ARGV.join(' '))
  end
end
