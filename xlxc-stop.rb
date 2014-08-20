#
# xlxc-stop: stop a Linux XIA container
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script stops a container and frees any IP addresses being
# used by the container.
#

 
require 'optparse'
require './xlxc'
require './xlxc-bridge'


USAGE = "Usage: ruby xlxc-stop.rb -n name"

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
    puts("xlxc-stop.rb must be run as root.")
    exit
  end

  # Check that there are no conflicts with the container name.
  name = options[:name]

  if name == nil
    puts("Specify name for container using -n or --name.")
    exit
  end
end

# Remove the IP address for this container and stop it.
#
def stop_container(options)
  name = options[:name]
  bridge = XLXC_BRIDGE.get_bridge(name)
  `rm #{File.join(XLXC_BRIDGE::BRIDGES, bridge, "containers", name)}`
  `lxc-stop -n #{name} --kill`
end

if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  stop_container(options)
end
