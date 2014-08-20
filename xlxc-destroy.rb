#
# xlxc-destroy: destroy Linux XIA containers
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script stops and destroys a Linux XIA container.
#


require 'fileutils'
require 'optparse'
require './xlxc'
require './xlxc-bridge'


USAGE = "\nUsage: ruby xlxc-destroy.rb -n name\n\n"

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

# Perform error checks on the parameters of the script and options.
#
def check_for_errors(options)
  # Check that user is root.
  if Process.uid != 0
    puts("xlxc-destroy.rb must be run as root.")
    exit
  end

  # Check that this container exists.
  name = options[:name]
  if name == nil
    puts("Specify name for container.")
    exit
  end
end

# Destroy a container filesystem by removing bind mounts.
#
def destroy_fs(rootfs)
  for dir in XLXC::BIND_MOUNTED_DIRECTORIES
    `umount -l #{File.join(rootfs, dir)}`
  end
end

# Destroy a container.
#
def destroy(options)
  name = options[:name]

  # Stop the container if it is still running.
  `lxc-stop -n #{name} --kill`

  # Decrement reference count to the Ethernet bridge.
  f = File.open(File.join(XLXC::LXC, name, "bridge"), "r")
  bridge = f.readline().strip()
  f.close()

  destroy_fs(File.join(XLXC::LXC, name, "rootfs"))

  `rm -rf #{File.join(XLXC::LXC, name)}`
  if File.exists?(File.join(XLXC_BRIDGE::BRIDGES, bridge, "containers", name))
    `rm #{File.join(XLXC_BRIDGE::BRIDGES, bridge, "containers", name)}`
  end
end


if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors(options)
  destroy(options)
end
