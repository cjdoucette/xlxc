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


USAGE = "Usage: ruby xlxc-start.rb -n name [--daemon]"

# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = USAGE

    options[:daemon] = false
    opts.on('-d', '--daemon', 'Start in daemon mode') do |name|
      options[:daemon] = true
    end

    options[:name] = nil
    opts.on('-n', '--name ARG', 'Container name') do |name|
      options[:name] = name
    end

    options[:path] = nil
    opts.on('-p', '--path ARG', 'Path of container') do |path|
      options[:path] = path
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

# Check to make sure that the container is set-up correctly and
# then start the container.
#
def start_container(options)
  name = options[:name]
  path = options[:path]
  XLXC.setup_net(name, path)
  XLXC.setup_fs(name)
  if options[:daemon]
    `lxc-start -n #{name} -d`
  else
    `lxc-start -n #{name}`
  end
end

if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  start_container(options)
end
