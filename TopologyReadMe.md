xlxc for arbitrary topologies
====

  * Using 'topoStruct' file first define structure of topology we want to build
  * By passing topology structure in 'network-create' file, first switches, hosts and links are added to the 	  network and then objects of hosts, switches and links created to build structure of topology. Hosts can also 	 be started using it. 
  * class Host and OVSSwitch in 'Node' and 'switch' files calls xlxc-bridges, xlxc-create/destroy, xlxc-start/	  stop files to create, configure, start xia container and OVS-bridge  

--------------------------------------------------------------
| New XLXC script   | purpose                                |
|-----------------  |----------------------------------------|
| topoStruct.rb     | To define structure of topology to be  |
|                   | built. 						         |
| network-create.rb | Adding hosts, switches and links to    |
|				    | network and create their instances.    |
| 			        | Also to configure and start the 	     |
| 			        | topology 							     |
| node.rb           | class for Host/Node, uses xia container|
| switch.rb         | class for OVS switch                   |
--------------------------------------------------------------

