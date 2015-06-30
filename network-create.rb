require 'pty'
require 'fileutils'
require 'io/console'
require './switch.rb'

class Create
  def initialize(topo=simpletopo)
    @topo = topo
    @hosts = []
    @switches = []
    @links = []

    @nameToNode = {}  # name to Node (Host/Switch) objects

    @terms = []  # list of spawned xterm processes
    build()
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
    for srcName, dstName, params in topo.links(sort=True, withInfo=True)
      addLink(srcName, dstName, params)      
    end

  end

  def addHost(name, *args)
    h = Host.new(name,args)
    @hosts.push(h)
    @nameToNode[name] = h
    return h
  end

  def addSwitch(name, *args)
    s = Host.new(name,args)
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
  
end

