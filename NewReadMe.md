xlxc for arbitrary topologies
====

To create a network topology (already defined in 'topoStruct' file, currently defined are tree and singleSwitch)

  # ruby network.rb -n name --create -t topology

  For example
  	# ruby network.rb -n xia --create -t tree


Process:

Structure of topology is defined in 'topoStruct' file, using network file switch and hosts are added and linked. 
'Node' and 'switch' files calls xlxc-bridges, xlxc-create/destroy, xlxc-start/	  stop files to create, configure, start xia container and OVS-bridge 




  * Using 'topoStruct' file first define structure of topology we want to build
  * By passing topology structure in 'network' file, first switches, hosts and links are added to the 	  network and then objects of hosts, switches and links created to build structure of topology. Hosts can also 	 be started using it. 
  * class Host and OVSSwitch in 'Node' and 'switch' files calls xlxc-bridges, xlxc-create/destroy, xlxc-start/	  stop files to create, configure, start xia container and OVS-bridge 

--------------------------------------------------------------
| New XLXC script   | Purpose                                |
|-----------------  |----------------------------------------|
| topoStruct.rb     | To define structure of topology to be  |
|                   | built. 						         |
| network.rb        | Adding hosts, switches and links to    |
|				    | network and create their instances.    |
| 			        | Also to configure and start the 	     |
| 			        | topology 							     |
| node.rb           | class for Host/Node, uses xia container|
| switch.rb         | class for OVS switch                   |
| link.rb           | class for link                         |
--------------------------------------------------------------

* To create desired topology build structure of topology in 'topoStruct' and pass it to the network
