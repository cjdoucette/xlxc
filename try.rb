require 'pty'
require 'fileutils'
require 'io/console'
require 'optparse'
require 'rubygems'
require 'netaddr'
require 'ipaddr'
require './xlxc'
require './xlxc-bridge'
require './xlxc-create'

XLXC.setup_net('ovsHost','/home/aryaman/gsoc/xlxc/bridges/')
XLXC.setup_fs('ovsHost')

`lxc-start -n ovsHost`
