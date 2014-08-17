#
# xlxc-destroy: destroy XIA-linux containers
#
# Author: Cody Doucette <doucette@bu.edu>
#
# This Ruby script stops and destroys a given number of IP or XIA linux
# containers. Each container uses a separate network bridge to the host,
# and this script destroys those bridges as well.
#
# This script is based on the lxc-destroy script written by:
#     Daniel Lezcano <daniel.lezcano@free.fr>
#


require 'fileutils'
require 'optparse'
require './xlxc'

USAGE = "Usage: ruby xlxc-destroy.rb {NAME START END | --delbrs}"

# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = USAGE

    options[:delbrs] = false
    opts.on('-d', '--delbrs', 'Delete all Ethernet bridges') do
      options[:delbrs] = true
    end

  end

  optparse.parse!
  return options
end

# Perform error checks on the parameters of the script and options
#
def check_for_errors(first, last, options)
  if options[:delbrs]
    puts("Deleting Ethernet bridges and quiting.")
    `rm -rf #{XLXC::BRIDGES}`
    exit
  end

  if ARGV.length != 3
    puts(USAGE)
    exit
  end

  if last < first
    puts("End parameter cannot be less than start parameter.")
    exit
  end

  # Check that user is root.
  if Process.uid != 0
    puts("xlxc-destroy must be run as root.")
    exit
  end
end

# Destroy a container filesystem by removing bind mounts.
#
def destroy_fs(rootfs)
  `umount -l #{File.join(rootfs, XLXC::USR)}`
  `umount -l #{File.join(rootfs, XLXC::SBIN)}`
  `umount -l #{File.join(rootfs, XLXC::LIB)}`
  `umount -l #{File.join(rootfs, XLXC::LIB64)}`
  `umount -l #{File.join(rootfs, XLXC::BIN)}`
end

# Destroy all containers beginning with name
# and numbered from first to last.
#
def destroy(name, first, last)
  for j in first..last
    container = name + j.to_s()

    # Stop the container if it is still running.
    `lxc-stop -n #{container} --kill`

    # Decrement reference count to the ethernet bridge.
    XLXC.dec_bridge_ref(name)

    rootfs = File.join(XLXC::LXC, container, "rootfs")
    destroy_fs(rootfs)
  end

  for j in first..last
    container = name + j.to_s()
    `rm -rf #{File.join(XLXC::LXC, container)}`
  end
end


if __FILE__ == $PROGRAM_NAME
  name = ARGV[0]
  first = ARGV[1].to_i()
  last = ARGV[2].to_i()
  options = parse_opts()
  check_for_errors(first, last, options)
  destroy(name, first, last)
end
