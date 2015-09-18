require 'pty'
require 'fileutils'
require 'io/console'
require './node.rb'

class OVSSwitch < Node
  "OVSBridge is an OVSSwitch in standalone/bridge mode"
  @@portBase = 1 

  def initialize(name, parent, path, cidr = '192.168.10.0/24', *args)
    super( name, parent, path, args )
    @cidr = cidr    
  end  

  def create()
    `ruby xlxc-bridge.rb -b #{@name} -c #{@cidr} -p #{@path}`
  end  

  def start()
    `ifconfig #{@name} up`
  end

  def stop()
    `ifconfig #{@name} down`
  end
  
  def destroy()
    `ovs-vsctl del-br #{@name}`
  end  

  def attach(intf)
    "Connect a data port"
    `ovs-vsctl add-port #{@name} eth#{intf}`
    #{}`ifconfig #{intf} up`
  end
    
  def detach(port)
    "Disconnect a data port"
    `ovs-vsctl del-port #{@name} #{port}`
  end

  def attachAll()
    for port in @intfs.keys
      attach(port)
    end  
  end     
  
    
  def addIntf(intf, port=nil)
    #@intfs[port] = intf
    if port == nil
      port = newPort()
    end  
    @ports[intf] = port
    @intfs[port] = intf  
  end

  def newPort()
    "Return the next port number to allocate."
    if @ports.length > 0
      return @ports.values.max + 1
    end  
    return @@portBase
  end

  def connectionsTo(node)
    "Return [ intf1, intf2... ] for all intfs that connect self to node."
    # We could optimize this if it is important
    connections = []
    for intf in intfList()
      link = intf.link
      if link
        node1, node2 = link.intf1.node, link.intf2.node
        if node1 == self and node2 == node
          connections += [intf, link.intf2 ]
        elsif node1 == node and node2 == self
          connections += [intf, link.intf1]
        end
      end
    end
    return connections
  end

  def intfList()
    "List of our interfaces sorted by port number"
    sortedkeys=@intfs.keys()
    return [for p in sortedkeys do @intfs[p] end]
  end

  def intfListNames()
    "List of our interfaces sorted by port number"
    sortedkeys=@intfs.values()
    return [for p in sortedkeys do @intfs[p] end]
  end  

  def intfNames()
    "The names of our interfaces sorted by port number"
    return [for i in intfListNames() do i end]
  end

  def portNumbers()
    "The names of our interfaces sorted by port number"
    return [for i in intfList() do i.to_s end]
  end

  def connectEth()
    `ovs-vsctl add-port #{@name} eth0`
    `ifconfig eth0 0`
    `dhclient #{@name}`    
  end 

  def self.portBase()
    return @@portBase
  end 

end
