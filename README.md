xlxc
====

Scripts for creating IP and XIA containers

XLXC allows users to create multiple, large networks of Linux containers (LXC) running Linux XIA (assuming
the host is also running an XIA kernel). The scripts in this repository are very similar to the scripts
available through the LXC project, but with the following features:

  * All scripts are written in Ruby, making it easy for users to customize the functionality they want.
  * XLXC provides a script for easily creating and deleting Ethernet bridges, allowing users to create
    more complicated topologies of containers.
  * XLXC provides a script for creating and deleting large networks of containers, allowing for quick
    testing at scale.
  * XLXC does not use DHCP to configure IP addresses. Instead, it maintains its own state information
    to assign unique address to containers, which makes booting a container instantaneous.

XLXC is currently built to work with Ubuntu 14.04 (Trusty Tahr).

The following table illustrates the similaries between LXC and XLXC:

| XLXC script     | purpose                                | LXC equivalent |
|-----------------|----------------------------------------|----------------|
| xlxc-create.rb  | Create a container                     | lxc-create     |
| xlxc-destroy.rb | Destroy a container                    | lxc-destroy    |
| xlxc-start.rb   | Start a container/attach console       | lxc-start      |
| xlxc-stop.rb    | Stop a container/detach console        | lxc-stop       |
| xlxc-bridge.rb  | Create/destroy an Ethernet bridge      | 1.             |
| xlxc-net.rb     | Create a network of bridges/containers | 2.             |
-----------------------------------------------------------------------------

1. LXC creates a single default bridge for containers to use.
2. LXC does not have any batching functionality.

Users can use xlxc-create.rb, xlxc-destroy.rb, and xlxc-bridge.rb individually to create containers.
However, the easiest way to create containers is to use xlxc-net.rb:

To create a network of ten containers all on the same bridge (where eth0 is the gateway interface of the host):

 # ruby xlxc-net.rb -n xia -s 10 -t connected -i eth0    # creates containers xia0, xia1, ..., xia9
 
To start a container:

 # ruby xlxc-start.rb -n xia0
 
To stop a container:

 # ruby xlxc-stop.rb -n xia0
 
To destroy the network:

 # ruby xlxc-net.rb -n xia -s 10 -t connected --del
 
More information is available here: https://github.com/AltraMayor/XIA-for-Linux/wiki/XIA-Linux-Containers-%28XLXC%29
