require 'pty'
require 'fileutils'
require 'io/console'
require './node.rb'

class Switch < Node
  """A Switch is a Node that is running (or has execed?)
     an OpenFlow switch."""

  @@portBase = 1  # Switches start with port 1 in OpenFlow
  @@dpidLen = 16  # digits in dpid passed to switch

  def initialize(name, dpid=nil, opts='', listenPort=nil, params)
    """dpid: dpid hex string (or nil to derive from name, e.g. s1 -> 1)
       opts: additional switch options
       listenPort: port to listen on for dpctl connections"""
    super(self, name, params)
    @dpid = defaultDpid(dpid)
    @opts = opts
    @listenPort = listenPort
    if not @inNamespace
      self.controlIntf = Intf('lo', self, port=0)
    end  
  end    
  
  def self.dpidLen()
    return @@dpidLen
  end
      
  def defaultDpid( dpid=nil )
    "Return correctly formatted dpid from dpid or switch name (s1 -> 1)"
    if dpid
      # Remove any colons and make sure it's a good hex number
      dpid = dpid.translate( nil, ':' )
      assert dpid.length <= @@dpidLen and dpid.to_i(16) >= 0
    else
      # Use hex of the first number in the switch name
      nums = re.findall( "\d+".inspect, @name )
      if nums
        dpid = nums[ 0 ].to_s(16) 
      else
        raise Exception( 'Unable to derive default datapath ID - '+
                 'please either specify a dpid or use a '+
                'canonical switch name such as s23.' )
      end
    end
    return '0' * ( @@dpidLen - dpid.length ) + dpid
  end
    
  def defaultIntf()
    "Return control interface"
    if self.controlIntf
      return self.controlIntf
    else
      return Node.defaultIntf()
    end
  end    


  def sendCmd(*cmd, kwargs )
    """Send command to Node.
       cmd: string"""
    kwargs.setdefault( 'printPid', false )
    if not @execed
      return Node.sendCmd( self, *cmd, kwargs )
    else
      error( '*** Error: %s has execed and cannot accept commands' %
           @name )
    end
  end    

  def connected( )
    "Is the switch connected to a controller? (override this method)"
    # Assume that we are connected by default to whatever we need to
    # be connected to. This should be overridden by any OpenFlow
    # switch, but not by a standalone bridge.
    debug( 'Assuming', repr( self ), 'is connected to a controller\n' )
    return true
  end 
     
  def stop(  deleteIntfs=true )
    """Stop switch
       deleteIntfs: delete interfaces? (true)"""
    if deleteIntfs
      deleteIntfs()
    end
  end    

  def __repr__()
    "More informative string representation"
    intfs = ( ( [ '%s:%s' % 
                for i in intfList() do [ i.name, i.IP() ] end] ).join(',') )
    return '<%s %s: %s pid=%s> ' % [
      self.__class__.__name__, @name, intfs, @pid ]
  end  
end


class UserSwitch < Switch 
  "User-space switch."

  @@dpidLen = 12

  def initialize(  name, dpopts='--no-slicing', kwargs )
    """Init.
       name: name for the switch
       dpopts: additional arguments to ofdatapath (--no-slicing)"""
    super( self, name, kwargs )
    pathCheck( 'ofdatapath', 'ofprotocol',
           moduleName='the OpenFlow reference user switch' +
                '(openflow.org)' )
    if @listenPort
      @opts += ' --listen=ptcp:%i ' % @listenPort
    else
      @opts += ' --listen=punix:/tmp/%s.listen' % @name
    end
    @dpopts = dpopts
  end  
    
  @classmethod
  def setup( cls )
    "Ensure any dependencies are loaded; if not, try to load them."
    if not os.path.exists( '/dev/net/tun' )
      moduleDeps( add=TUN )
    end
  end    

  def dpctl(  *args )
    "Run dpctl command"
    listenAddr = nil
    if not @listenPort
      listenAddr = 'unix:/tmp/%s.listen' % @name
    else
      listenAddr = 'tcp:127.0.0.1:%i' % @listenPort
    end
      
    return cmd( 'dpctl ' + args.join(' ') +
             ' ' + listenAddr )
  end
    
  def connected( )
    "Is the switch connected to a controller?"
    status = dpctl( 'status' )
    return (  status.include? 'remote.is-connected=true' and
          status.include? 'local.is-connected=true') 
  end  

  @staticmethod
  def tcreapply( intf )
    """Unfortunately user switch and Mininet are fighting
       over tc queuing disciplines. To resolve the conflict,
       we re-create the user switch's configuration, but as a
       leaf of the TCIntf-created configuration."""
    if intf.is_a? TCIntf
      ifspeed = 10000000000  # 10 Gbps
      minspeed = ifspeed * 0.001

      res = intf.config( intf.params )

      if res is nil # link may not have TC parameters
        return
      end  
      # Re-add qdisc, root, and default classes user switch created, but
      # with new parent, as setup by Mininet's TCIntf
      parent = res['parent']
      intf.tc( "%s qdisc add dev %s " + parent +
           " handle 1: htb default 0xfffe" )
      intf.tc( "%s class add dev %s classid 1:0xffff parent 1: htb rate " + ifspeed.to_s )
      intf.tc( "%s class add dev %s classid 1:0xfffe parent 1:0xffff " +
           "htb rate " + minspeed.to_s + " ceil " + ifspeed.to_s )
    end
  end
      
  def start(  controllers )
    """Start OpenFlow reference user datapath.
       Log to /tmp/sN-{ofd,ofp}.log.
       controllers: list of controller objects"""
    # Add controllers
    clist = ( [ 'tcp:%s:%d' % 
              for c in controllers do [ c.IP(), c.port ] end ] ).join(',')
    ofdlog = '/tmp/' + @name + '-ofd.log'
    ofplog = '/tmp/' + @name + '-ofp.log'
    intfs = [ for i in intfList() do 
          if not i.IP() 
            ( i ).to_s end 
                  end ]
    cmd( 'ofdatapath -i ' + ','.join( intfs ) +
          ' punix:/tmp/' + @name + ' -d %s ' % @dpid +
          @dpopts +
          ' 1> ' + ofdlog + ' 2> ' + ofdlog + ' &' )
    cmd( 'ofprotocol unix:/tmp/' + @name +
          ' ' + clist +
          ' --fail=closed ' + @opts +
          ' 1> ' + ofplog + ' 2>' + ofplog + ' &' )
    if  not @dpopts.include? "no-slicing"
      # Only tcreapply if slicing is enable
      sleep(1)  # Allow ofdatapath to start before re-arranging qdisc's
      for intf in intfList()
        if not intf.IP()
          tcreapply( intf )
        end
      end
    end
  end        

  def stop(  deleteIntfs=true )
    """Stop OpenFlow reference user datapath.
       deleteIntfs: delete interfaces? (true)"""
    cmd( 'kill %ofdatapath' )
    cmd( 'kill %ofprotocol' )
    super( UserSwitch, self ).stop( deleteIntfs )
  end  

end


class OVSSwitch < Switch 
  "Open vSwitch switch. Depends on ovs-vsctl."

  def initialize(  name, failMode='secure', datapath='kernel',
          inband=false, protocols=nil,
          reconnectms=1000, stp=false, batch=false, params )
    """name: name for switch
       failMode: controller loss behavior (secure|open)
       datapath: userspace or kernel mode (kernel|user)
       inband: use in-band control (false)
       protocols: use specific OpenFlow version(s) (e.g. OpenFlow13)
            Unspecified (or old OVS version) uses OVS default
       reconnectms: max reconnect timeout in ms (0/nil for default)
       stp: enable STP (false, requires failMode=standalone)
       batch: enable batch startup (false)"""
    super( self, name, params )
    @failMode = failMode
    @datapath = datapath
    @inband = inband
    @protocols = protocols
    @reconnectms = reconnectms
    @stp = stp
    @_uuids = []  # controller UUIDs
    @batch = batch
    @commands = []  # saved commands for batch startup
  end

  @classmethod
  def setup( cls )
    "Make sure Open vSwitch is installed and working"
    pathCheck( 'ovs-vsctl',
           moduleName='Open vSwitch (openvswitch.org)')
    # This should no longer be needed, and it breaks
    # with OVS 1.7 which has renamed the kernel module:
    #  moduleDeps( subtract=OF_KMOD, add=OVS_KMOD )
    out, err, exitcode = errRun( 'ovs-vsctl -t 1 show' )
    if exitcode
      error( out + err +
           'ovs-vsctl exited with code %d\n' % exitcode +
           '*** Error connecting to ovs-db with ovs-vsctl\n'+
           'Make sure that Open vSwitch is installed, '+
           'that ovsdb-server is running, and that\n'+
           '"ovs-vsctl show" works correctly.\n'+
           'You may wish to try '+
           '"service openvswitch-switch start".\n' )
      exit( 1 )
    end
    version = quietRun( 'ovs-vsctl --version' )
    cls.OVSVersion = findall( "\d+\.\d+".inspect, version )[ 0 ]
  end
    
  @classmethod
  def isOldOVS( cls )
    "Is OVS ersion < 1.10?"
    return ( StrictVersion( cls.OVSVersion ) <
         StrictVersion( '1.10' ) )
  end
    
  def dpctl(  *args )
    "Run ovs-ofctl command"
    return cmd( 'ovs-ofctl', args[ 0 ], self, *args[ 1..args.length ] )
  end
    
  def vsctl(  *args, kwargs )
    "Run ovs-vsctl command (or queue for later execution)"
    if @batch
      cmd = (  for arg in args do ( arg ).to_s.strip() end ).join(' ')
      @commands.append( cmd )
    else
      return cmd( 'ovs-vsctl', *args, kwargs )
    end
  end

  @staticmethod
  def tcreapply( intf )
    """Unfortunately OVS and Mininet are fighting
       over tc queuing disciplines. As a quick hack/
       workaround, we clear OVS's and reapply our own."""
    if intf.is_a? TCIntf
      intf.config( intf.params )
    end
  end    

  def attach(  intf )
    "Connect a data port"
    vsctl( 'add-port', self, intf )
    cmd( 'ifconfig', intf, 'up' )
    tcreapply( intf )
  end
    
  def detach(  intf )
    "Disconnect a data port"
    vsctl( 'del-port', self, intf )
  end
    
  def controllerUUIDs(  update=false )
    """Return ovsdb UUIDs for our controllers
       update: update cached value"""
    if not @_uuids or update
      controllers = cmd( 'ovs-vsctl -- get Bridge', self,
                  'Controller' ).strip()
      if controllers.start_with?( '[' ) and controllers.end_with?( ']' )
        controllers = controllers[ 1 .. -1 ]
        if controllers
          @_uuids = [ 
                  for c in controllers.split( ',' ) do c.strip() end]
        end
      end
    end                
    return @_uuids
  end
    
  def connected( )
    "Are we connected to at least one of our controllers?"
    for uuid in controllerUUIDs()
      if vsctl( '-- get Controller',
                   uuid, 'is_connected' ).include? 'true'
        return true
      end
    end    
    return @failMode == 'standalone'
  end  

  def intfOpts(  intf )
    "Return OVS interface options for intf"
    opts = ''
    if not isOldOVS()
      # ofport_request is not supported on old OVS
      opts += ' ofport_request=%s' % self.ports[ intf ]
      # Patch ports don't work well with old OVS
      if isinstance( intf, OVSIntf )
        intf1, intf2 = intf.link.intf1, intf.link.intf2
        peer = intf1 if intf1 != intf else intf2
        opts += ' type=patch options:peer=%s' % peer
      end
    end   

    ret =  if not opts 
          ''
        else 
          ' -- set Interface %s' % intf + opts 
        end 
    
    return ret
  end  

  def bridgeOpts( )
    "Return OVS bridge options"
    opts = ( ' other_config:datapath-id=%s' % @dpid +
         ' fail_mode=%s' % @failMode )
    if not @inband
      opts += ' other-config:disable-in-band=true'
    end

    if @datapath == 'user'
      opts += ' datapath_type=netdev'
    end

    if @protocols and not isOldOVS()
      opts += ' protocols=%s' % @protocols
    end

    if @stp and @failMode == 'standalone'
      opts += ' stp_enable=true' % self
    end
    
    return opts
  end  

  def start(  controllers )
    "Start up a new OVS OpenFlow switch using ovs-vsctl"
    if @inNamespace
      raise Exception(
        'OVS kernel switch does not work in a namespace' )
    end  
    @dpid.to_i(16)  # DPID must be a hex string
    # Command to add interfaces
    intfs = ''.join( ' -- add-port %s %s' % [self, intf ] +
             for intf in intfList() do
             if self.ports[ intf ] and not intf.IP()
              self.intfOpts( intf ) end end )
    # Command to create controller entries
    clist = [  @name + c.name, '%s:%s:%d' %
          for c in controllers do [ c.protocol, c.IP(), c.port ] end ]

    if @listenPort
      clist.append( @name + '-listen',
              'ptcp:%s' % @listenPort)
    end  
    ccmd = '-- --id=@%s create Controller target=\\"%s\\"'
    if @reconnectms
      ccmd += ' max_backoff=%d' % @reconnectms
    end
    cargs = (  for name, target in clist do ccmd % [ name, target ] end).join(' ')
    # Controller ID list
    cids = (  for name, _target in clist do '@%s' % name end).join(',')
    # Try to delete any existing bridges with the same name
    if not isOldOVS()
      cargs += ' -- --if-exists del-br %s' % self
    end  
    # One ovs-vsctl command to rule them all!
    vsctl( cargs +
          ' -- add-br %s' % self +
          ' -- set bridge %s controller=[%s]' % [ self, cids  ] +
          self.bridgeOpts() +
          intfs )
    # If necessary, restore TC config overwritten by OVS
    if not @batch
      for intf in intfList()
        tcreapply( intf )
      end
    end
  end      
  # This should be ~ int( quietRun( 'getconf ARG_MAX' ) ),
  # but the real limit seems to be much lower
  @@argmax = 128000
  def self.argmax()
    return @@argmax
  end
  @classmethod
  def batchStartup( cls, switches, run=errRun )
    """Batch startup for OVS
       switches: switches to start up
       run: function to run commands (errRun)"""
    info( '...' )
    cmds = 'ovs-vsctl'
    for switch in switches
      if switch.isOldOVS()
        # Ideally we'd optimize this also
        run( 'ovs-vsctl del-br %s' % switch )
      end
        
      for cmd in switch.commands do
        cmd = cmd.strip()
        # Don't exceed ARG_MAX
        if cmd.length + cmd.length >= cls.argmax
          run( cmds, shell=true )
          cmds = 'ovs-vsctl'
        end
        cmds += ' ' + cmd
        switch.cmds = []
        switch.batch = false
      end 
    end
         
    if cmds
      run( cmds, shell=true )
    end
    # Reapply link config if necessary...
    for switch in switches
      for intf in switch.intfs.itervalues()
        if intf.is_a? TCIntf #isinstance( intf, TCIntf ):
          intf.config( intf.params )
        end
      end
    end
          
    return switches
  end  

  def stop(  deleteIntfs=true )
    """Terminate OVS switch.
       deleteIntfs: delete interfaces? (true)"""
    cmd( 'ovs-vsctl del-br', self )
    if @datapath == 'user'
      cmd( 'ip link del', self )
    end  
    super( OVSSwitch, self ).stop( deleteIntfs )
  end
    
  @classmethod
  def batchShutdown( cls, switches, run=errRun )
    "Shut down a list of OVS switches"
    delcmd = 'del-br %s'
    if switches and not switches[ 0 ].isOldOVS()
      delcmd = '--if-exists ' + delcmd
    end  
    # First, delete them all from ovsdb
    run( 'ovs-vsctl ' +
       (  for s in switches do delcmd % s end).join(' -- ') )
    # Next, shut down all of the processes
    pids = ' '.join(for switch in switches do ( switch.pid ).to_s end)
    run( 'kill -HUP ' + pids )
    for switch in switches
      switch.shell = nil
    end  
    return switches
  end
end

OVSKernelSwitch = OVSSwitch


class OVSBridge < OVSSwitch 
  "OVSBridge is an OVSSwitch in standalone/bridge mode"

  def initialize(  *args, kwargs )
    """stp: enable Spanning Tree Protocol (false)
       see OVSSwitch for other options"""
    kwargs.merge!( failMode='standalone' )
    super( self, *args, kwargs )
  end  

  def start(  controllers )
    "Start bridge, ignoring controllers argument"
    OVSSwitch.start( self, controllers=[] )
  end
    
  def connected()
    "Are we forwarding yet?"
    if @stp
      status = dpctl( 'show' )
      x = status.include? 'STP_FORWARD'
      y = (status.include? 'STP_LEARN')
      res = x and y
      return res
    else
      return true
    end  
  end   
end

ovs=OVSSwitch.new()
