require 'pty'
require 'fileutils'
require 'io/console'
require './switch.rb'
require './topoStruct'

class Network
  
  attr_reader :topo
  attr_reader :nameToNode

  def initialize(topo=SingleSwitchTopo.new()) 
  
    @topo = topo
    @hosts = []
    @switches = []
    @links = []
    @hslinks = []
    @slinks = []
    @nameToNode = {}  # name to Node (Host/Switch) objects
    build()
    create()
  end

  def build()
    #adding hosts
    for hostName in topo.hosts()
      addHost(hostName, topo.nodeInfo(hostName))
    end  
            
    #adding switches        
    for switchName in topo.switches()
      addSwitch(switchName, topo.nodeInfo(switchName))
    end

    #adding links
    #for srcName, dstName in topo.links
    #  addLink(srcName, dstName)      
    #end
    """
    #adding links b/w switches
    for srcName, dstName in topo.switchLinks()
      addSwitchLink(srcName, dstName)      
    end

    #adding links b/w switch and host
    for host,switch in topo.hslinks()
      addHsLinks(host, switch)      
    end    
    """
  end
  

  def getNodeByName( *args )
    "Return node(s) with given name(s)"
    names = []
    for n in args
      names.push(@nameToNode[n])
    end
    return names
  end

  def get( *args )
    return getNodeByName(*args)
  end       
  
  def addHost(name, *args)
    parent = topo.graph.node[name].fetch('parent')
    path = topo.graph.node[name].fetch('path')
    h = Host.new(name, parent, path)
    @hosts.push(h)
    @nameToNode[name] = h
    return h
  end

  def addSwitch(name, *args)

    parent = topo.graph.node[name].fetch('parent')
    path = topo.graph.node[name].fetch('path')
    s = OVSSwitch.new(name, parent, path)
    @switches.push(s)
    @nameToNode[name] = s
    return s
  end
  
  def addLink(node1, node2, *options)
    """
    node1 = node1 if not isinstance( node1, basestring ) else self[ node1 ]
    node2 = node2 if not isinstance( node2, basestring ) else self[ node2 ]
    options = dict( params )
        # Port is optional
        if port1 is not None:
            options.setdefault( 'port1', port1 )
        if port2 is not None:
            options.setdefault( 'port2', port2 )
        if self.intf is not None:
            options.setdefault( 'intf', self.intf )
        # Set default MAC - this should probably be in Link
        options.setdefault( 'addr1', self.randMac() )
        options.setdefault( 'addr2', self.randMac() )
    """    
    l = link( node1, node2, *options )
    @links.push(l)
    return l
  end
  
  def addSwitchLinks(switch1, switch2)
    l = link( switch1, switch2, *options )
    @slinks.push(l)
    return l
  end

  def addHsLinks(host, switch)
    l = link( node1, node2, *options )
    @hslinks.push(l)
    return l
  end

  def create()
    for switch in @switches
      switch.create()
    end

    for host in @hosts
      host.create()
    end  
  end
  
  def start()
    for host in @hosts
      host.start()
    end
  end

  def stop()
    for host in @hosts
      host.stop()
    end
  end  
  
end

$mynet = Network.new(TreeTopo.new(3,2))
$mynet.start() 
#$mynet = Network.new() 
