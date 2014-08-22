#
# xlxc-execute: execute a command in a Linux XIA container
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script starts a Linux XIA container and executes a command
# inside it.
#

 
require 'optparse'
require './xlxc'
require './xlxc-bridge'


USAGE = "\nUsage: ruby xlxc-execute.rb -n name -- command\n\n"

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
    puts("xlxc-execute.rb must be run as root.")
    exit
  end

  # Check that there are no conflicts with the container name.
  name = options[:name]

  if name == nil
    puts("Specify name for container using -n or --name.")
    exit
  end

  if ARGV.length <= 0
    puts("Specify a command to run in the container.")
    exit
  end
end

# Execute a given command inside a container.
#
def execute_container(options)
  name = options[:name]
  command = ARGV.join(' ')
  XLXC.setup_net(name)
  XLXC.setup_fs(name)
  `lxc-execute -n #{name} -- #{command}`
end

if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  execute_container(options)
end
