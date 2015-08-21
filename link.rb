"""
link.py: interface and link abstractions for mininet

It seems useful to bundle functionality for interfaces into a single
class.

Also it seems useful to enable the possibility of multiple flavors of
links, including:

- simple path pairs
- tunneled links
- patchable links (which can be disconnected and reconnected via a patchbay)
- link simulators (e.g. wireless)

Basic division of labor:

  Nodes: know how to execute commands
  Intfs: know how to configure themselves
  Links: know how to connect nodes together

Intf: basic interface object that can configure itself
TCIntf: interface with bandwidth limiting and delay via tc

Link: basic link class for creating veth pairs
"""

require './node'
import r.

class Intf

  "Basic interface object that can configure itself."

  def initialize( name, node=nil, port=nil, link=nil,
          mac=nil, **params )
    """name: interface name (e.g. h1-eth0)
       node: owning node (where this intf most likely lives)
       link: parent link if we're part of a link
       other arguments are passed to config()"""
    @node = node
    @name = name
    @link = link
    @mac = mac
    @ip = nil
    @prefixLen = nil

    # if interface is lo, we know the ip is 127.0.0.1.
    # This saves an ifconfig command per node
    if @name == 'lo'
      @ip = '127.0.0.1' 
    end
    # Add to node (and move ourselves if necessary )
    moveIntfFn = params.pop( 'moveIntfFn', nil )
    if moveIntfFn
      node.addIntf( self, port=port, moveIntfFn=moveIntfFn )
    else
      node.addIntf( self, port=port )
    end  
    # Save params for future reference
    self.params = params
    config(params)
  end

  def ifconfig(*args)
    "Configure ourselves using ifconfig"
    `ifconfig #{@name} #{args}`
  end  

  def setIP( ipstr, prefixLen=nil )
    """Set our IP address"""
    # This is a sign that we should perhaps rethink our prefix
    # mechanism and/or the way we specify IP addresses
    if (ipstr.include? '/')
      @ip, @prefixLen = ipstr.split( '/' )
      return ifconfig( ipstr, 'up' )
    else
      if prefixLen == nil
        raise Exception( 'No prefix length set for IP address %s'
                 % ( ipstr ) )
      end  
      @ip = ipstr 
      @prefixLen = prefixLen
      return ifconfig( '%s/%s' % [ipstr, prefixLen ] )
    end  
  end    

  def setMAC(macstr)
    """Set the MAC address for an interface.
       macstr: MAC address as string"""
    @mac = macstr
    return ( ifconfig( 'down' ) +
         ifconfig( 'hw', 'ether', macstr ) +
         ifconfig( 'up' ) )
  end  
  #_ipMatchRegex = re.compile( r'\d+\.\d+\.\d+\.\d+' )
  #_macMatchRegex = re.compile( r'..:..:..:..:..:..' )

  def updateIP()
    "Return updated IP address based on ifconfig"
    # use pexec instead of node.cmd so that we dont read
    # backgrounded output from the cli.
    ifconfig, _err, _exitCode = @node.pexec(
      'ifconfig %s' % @name )
    ips = self._ipMatchRegex.findall( ifconfig )
    @ip = ips[0] if ips else nil
    return @ip

  def updateMAC( self ):
    "Return updated MAC address based on ifconfig"
    ifconfig = ifconfig()
    macs = self._macMatchRegex.findall( ifconfig )
    @mac = macs[0] if macs else nil
    return @mac
  end  
  # Instead of updating ip and mac separately,
  # use one ifconfig call to do it simultaneously.
  # This saves an ifconfig command, which improves performance.

  def updateAddr()
    "Return IP address and MAC address based on ifconfig."
    ifconfig = ifconfig()
    ips = self._ipMatchRegex.findall( ifconfig )
    macs = self._macMatchRegex.findall( ifconfig )
    @ip = ips[0] if ips else nil
    @mac = macs[0] if macs else nil
    return @ip, @mac
  end  

  def IP()
    "Return IP address"
    return @ip
  end  

  def MAC()
    "Return MAC address"
    return @mac
  end  

  def isUp(  setUp=false ):
    "Return whether interface is up"
    if setUp
      cmdOutput = ifconfig( 'up' )
      # no output indicates success
      if cmdOutput
        error( "Error setting %s up: %s " % ( @name, cmdOutput ) )
        return false
      else
        return true
      end  
    else
      return "UP" in ifconfig()
    end
  end    

  def rename( newname )
    "Rename interface"
    ifconfig( 'down' )
    result = `ip link set #{@name} name #{newname}`
    @name = newname
    ifconfig( 'up' )
    return result
  end  

  # The reason why we configure things in this way is so
  # That the parameters can be listed and documented in
  # the config method.
  # Dealing with subclasses and superclasses is slightly
  # annoying, but at least the information is there!

  def setParam(  results, method, **param )
    """Internal method: configure a *single* parameter
       results: dict of results to update
       method: config method name
       param: arg=value (ignore if value=nil)
       value may also be list or dict"""
    name, value = param.items()[0]
    f = getattr( self, method, nil )
    if not f or value is nil:
      return
    if isinstance( value, list ):
      result = f( *value )
    elif isinstance( value, dict ):
      result = f( **value )
    else:
      result = f( value )
    results[ name ] = result
    return result
  end
    
  def config(  mac=nil, ip=nil, ifconfig=nil,
        up=true, **_params )
    """Configure Node according to (optional) parameters:
       mac: MAC address
       ip: IP address
       ifconfig: arbitrary interface configuration
       Subclasses should override this method and call
       the parent class's config(**params)"""
    # If we were overriding this method, we would call
    # the superclass config method here as follows:
    # r = Parent.config( **params )
    r = {}
    self.setParam( r, 'setMAC', mac=mac )
    self.setParam( r, 'setIP', ip=ip )
    self.setParam( r, 'isUp', up=up )
    self.setParam( r, 'ifconfig', ifconfig=ifconfig )
    return r
  end  

  def delete()
    "Delete interface"
    `ip link del #{@name}`
    # We used to do this, but it slows us down:
    # if @node.inNamespace:
    # Link may have been dumped into root NS
    # quietRun( 'ip link del ' + @name )
  end
    
  def status()
    "Return intf status as a string"
    links, _err, _result = @node.pexec( 'ip link show' )
    if @name in links
      return "OK"
    else
      return "MISSING"
    end
  end    

  def __repr__( self ):
    return '<%s %s>' % ( self.__class__.__name__, @name )
  end
    
  def __str__()
    return @name
  end  
end

class Link

  """A basic link is just a path pair."""
  def initialize( node1, node2, port1=nil, port2=nil,
          intfName1=nil, intfName2=nil, addr1=nil, addr2=nil,
          intf=Intf, params1=nil,
          params2=nil, fast=true ):
    """Create path link to another node, making two new interfaces.
       node1: first node
       node2: second node
       port1: node1 port number (optional)
       port2: node2 port number (optional)
       intf: default interface class/constructor
       intfName1: node1 interface name (optional)
       intfName2: node2  interface name (optional)
       params1: parameters for interface 1
       params2: parameters for interface 2"""
    # This is a bit awkward; it seems that having everything in
    # params is more orthogonal, but being able to specify
    # in-line arguments is more convenient! So we support both.
    if params1 == nil
      params1 = {}
    end
      
    if params2 is nil
      params2 = {}
    end  
    # Allow passing in params1=params2
    if params2 is params1
      params2 = dict( params1 )
    end
      
    if !port1
      params1['port'] = port1
    end

    if !port2
      params2['port'] = port2
    end
      
    if !(params1.include? 'port') 
      params1['port'] = node1.newPort()
    end
      
    if !(params1.include? 'port')
      params2['port'] = node2.newPort()
    end

    if !intfName1
      intfName1 = intfName( node1, params1['port'] )
    end
      
    if !intfName2
      intfName2 = self.intfName( node2, params2['port'] )
    end
      
    if fast
      makeIntfPair( intfName1, intfName2, addr1, addr2, deleteIntfs=false )
    else
      makeIntfPair( intfName1, intfName2, addr1, addr2 )
    end  

    @intf1 = Intf.new( name=intfName1, node=node1,
            link=self, mac=addr1, params1  )
    @intf2 = Intf.new( name=intfName2, node=node2,
            link=self, mac=addr2, params2 )
  end  
    
  def intfName(node, n)
    "Construct a canonical interface name node-ethN for interface n."
    return node.name + '-eth' + repr( n )
  end  

  @classmethod
  def makeIntfPair( intfname1, intfname2, addr1=nil, addr2=nil, deleteIntfs=true )
  """Make a veth pair connnecting new interfaces intf1 and intf2
     intf1: name for interface 1
     intf2: name for interface 2
     addr1: MAC address for interface 1 (optional)
     addr2: MAC address for interface 2 (optional)
     node1: home node for interface 1 (optional)
     node2: home node for interface 2 (optional)
     deleteIntfs: delete intfs before creating them
     raises Exception on failure"""
    if deleteIntfs
        # Delete any old interfaces with the same names
      `ip link del #{intf1}`
      `ip link del #{intf2}` 
    end  
      # Create new pair
    netns = 1
    if addr1 is nil and addr2 is nil
      cmdOutput = `ip link add name #{intf1} type veth peer name #{intf2} netns #{netns}`
      
    else
      cmdOutput = `ip link add name #{intf1} address #{addr1} type veth 
      peer name #{intf2} address #{addr2} netns #{netns}`
    end
        
    if cmdOutput
      raise Exception( "Error creating interface pair (%s,%s): %s " %
                 ( intf1, intf2, cmdOutput ) )
    end
  end

  def delete()
    "Delete this link"
    @intf1.delete()
    # We only need to delete one side, though this doesn't seem to
    # cost us much and might help subclasses.
    # @intf2.delete()
  end  

  def status()
    "Return link status as a string"
    return "(%s %s)" % [ @intf1.status(), @intf2.status() ]
  end
    
  def __str__()
    return '%s<->%s' % [@intf1, @intf2]
  end
    
end