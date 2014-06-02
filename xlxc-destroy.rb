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


# Remove LXC from a container.
#
def remove_lxc(rootfs)
  XLXC::LXC_FILES.each do |f|
    `umount #{File.join(rootfs, f)}`
  end
end

# Destroy all containers beginning with name and numbered
# from first to last.
#
def destroy(name, first, last)
  for j in first..last
    container = name + j.to_s()
    `lxc-stop -n #{container}`

    rootfs = File.join(XLXC::LXC, container, "rootfs")

    `umount #{File.join(rootfs, XLXC::MODULES)}`
    `umount #{File.join(rootfs, XLXC::XIP)}`
    `umount #{File.join(rootfs, XLXC::LIBXIA)}`
    `umount #{File.join(rootfs, XLXC::XIA_DATA)}`
    remove_lxc(rootfs)

    # Destroy the ethernet bridge to this container.
    `ifconfig #{container}br promisc down`
    `lxc-destroy -n #{container}`
    `rm -rf #{File.join(XLXC::LXC, container)}`
    `brctl delbr #{container}br`
  end
end

# Parse the command and organize the options.
#
def parse_opts()
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: ./xlxc-destroy NAME START_INDEX END_INDEX"
  end

  optparse.parse!
  return options
end

# Perform error checks on the parameters of the script and options
#
def check_for_errors()
  first = ARGV[1].to_i()
  last = ARGV[2].to_i()

  if ARGV.length != 3
    puts("Usage: ruby xlxc-destroy.rb NAME START_INDEX END_INDEX")
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


if __FILE__ == $PROGRAM_NAME
  options = parse_opts()
  check_for_errors()
  destroy(ARGV[0], ARGV[1].to_i(), ARGV[2].to_i())
end
