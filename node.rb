require 'pty'
require 'fileutils'
require 'io/console'

"""
import os
import pty
import re
import signal
import select
from subprocess import Popen, PIPE
from time import sleep

from mininet.log import info, error, warn, debug
from mininet.util import ( quietRun, errRun, errFail, moveIntf, isShellBuiltin,
                           numCores, retry, mountCgroups )
from mininet.moduledeps import moduleDeps, pathCheck, TUN
from mininet.link import Link, Intf, TCIntf, OVSIntf
from re import findall
from distutils.version import StrictVersion
"""


class Node
    """A virtual network node is simply a shell in a network namespace.
       We communicate with it using pipes."""

    @@portBase = 0  # Nodes always start with eth0/port0, even in OF 1.0

    def initialize( name, inNamespace=true, params )
        """name: name of node
           inNamespace: in network namespace?
           privateDirs: list of private directory strings or tuples
           params: Node parameters (see config() for details)"""

        # Make sure class actually works
        checkSetup()

        @name = params.fetch( 'name', name )
        @privateDirs = params.fetch( 'privateDirs', [] )
        @inNamespace = params.fetch( 'inNamespace', inNamespace )

        # Stash configuration parameters for future reference
        @params = params

        @intfs = Hash.new  # dict of port numbers to interfaces
        @ports = Hash.new  # dict of interfaces to port numbers
                         # replace with Port objects, eventually ?
        @nameToIntf = Hash.new  # dict of interface names to Intfs

        
        @shell=nil 
        @execed=nil 
        @pid=nil
        @stdin=nil 
        @stdout=nil
        @lastPid=nil 
        @lastCmd=nil 
        @pollOut  = nil

        @waiting = false
        @readbuf = ''

        # Start command interpreter shell
        startShell()
        mountPrivateDirs()   
    end
    

    # File descriptor to node mapping support
    # Class variables and methods

    @@inToNode = Hash.new  # mapping of input fds to nodes
    @@outToNode = Hash.new  # mapping of output fds to Nodes
    
    def self.portBase()
        return @@portBase
    end        

    def self.inToNode()
        return @@inToNode
    end

    def self.outToNode()
        return @@outToNode
    end    

    @classmethod
    def fdToNode( cls, fd )
        """Return node corresponding to given file descriptor.
           fd: file descriptor
           returns: node"""
        node = cls.outToNode.fetch( fd )
        
        """recheck"""
        x = node
        y = cls.inToNode.fetch( fd )
        res = x or y
        return res 
    end
        
    # Command support via shell process in namespace
    def startShell( mnopts=nil )
        "Start a shell process for running commands"
        if @shell
            error( "%s: shell is already running\n" % @name )
            return
        end    
        # mnexec: (c)lose descriptors, (d)etach from tty,
        # (p)rint pid, and run in (n)amespace
        if !mnopts
            opts='-cd'
        else
            opts=mnopts 
        end       
        #opts = '-cd' if !mnopts else mnopts
        if @inNamespace
            opts += 'n'
        end    
        # bash -i: force interactive
        # -s: pass $* to shell, and make process easy to find in ps
        # prompt is set to sentinel chr( 127 )
        cmd = [ 'mnexec', opts, 'env', 'PS1=' + 127.chr,
                'bash', '--norc', '-is', 'mininet:' + @name ]
        # Spawn a shell subprocess in a pseudo-tty, to disable buffering
        # in the subprocess and insulate it from signals (e.g. SIGINT)
        # received by the parent
        master, slave = PTY.open
        #master, slave = pty.openpty()
        @shell = _popen( cmd, stdin=slave, stdout=slave, stderr=slave,
                                  close_fds=false )
        @stdin = File.new(master, "rw")
        #@stdin = os.fdopen( master, 'rw' )
        @stdout = @stdin
        @pid = @shell.pid
        @pollOut = select.poll()

        @pollOut.register( @stdout )
        # Maintain mapping between file descriptors and nodes
        # This is useful for monitoring multiple nodes
        # using select.poll()
        @@outToNode[ @stdout.fileno() ] = self
        @@inToNode[ @stdin.fileno() ] = self
        @execed = false
        @lastCmd = nil
        @lastPid = nil
        @readbuf = ''
        # Wait for prompt
        while true
            data = read( 1024 )
            if data[ -1 ] == 127.chr
                break
            end    
            @pollOut.poll()
        end    
        @waiting = false
        # +m: disable job control notification
        cmd( 'unset HISTFILE; stty -echo; set +m' )
    end

    def mountPrivateDirs()
        "mount private directories"
        for directory in @privateDirs do
            if directory.is_a tuple
                # mount given private directory
                privateDir = directory[ 1 ] % self.__dict__
                mountPoint = directory[ 0 ]
                cmd( 'mkdir -p %s' % privateDir )
                cmd( 'mkdir -p %s' % mountPoint )
                cmd( 'mount --bind %s %s' %
                               [ privateDir, mountPoint ] )
            else
                # mount temporary filesystem on directory
                cmd( 'mkdir -p %s' % directory )
                cmd( 'mount -n -t tmpfs tmpfs %s' % directory )
            end
        end         
    end

    def unmountPrivateDirs()
        "mount private directories"
        for directory in @privateDirs do
            if directory.is_a tuple
                cmd( 'umount ', directory[ 0 ] )
            else
                cmd( 'umount ', directory )
            end
        end         
    end

    def _popen( cmd, params )
        """Internal method: spawn and return a process
            cmd: command to run (list)
            params: parameters to Popen()"""
        # Leave this is as an instance method for now
        assert self
        return IO.popen( cmd, params )
    end    

    def cleanup()
        "Help python collect its garbage."
        # We used to do this, but it slows us down:
        # Intfs may end up in root NS
        # for intfName in self.intfNames():
        # if @name in intfName:
        # quietRun( 'ip link del ' + intfName )
        @shell = nil
    end
    # Subshell I/O, commands and control

    def read( maxbytes=1024 )
        """Buffered read from node, non-blocking.
           maxbytes: maximum number of bytes to return"""
        count = @readbuf.length
        if count < maxbytes
            data = File.new(@stdout.fileno(), "r").sysread(maxbytes - count)
            #data = os.read( @stdout.fileno(), maxbytes - count )
            @readbuf += data
        end    

        if maxbytes >= @readbuf.length
            result = @readbuf
            @readbuf = ''
        else
            result = @readbuf[0 .. maxbytes ]
            @readbuf = @readbuf[ maxbytes .. @readbuf.length ]
        end

        return result
    end    

    def readline()
        """Buffered readline from node, non-blocking.
           returns: line (minus newline) or nil"""
        @readbuf += read( 1024 )
        if !@readbuf.index('\n')
            return nil
        end    
        pos = @readbuf.index( '\n' )
        line = @readbuf[ 0... pos ]
        @readbuf = @readbuf[ pos + 1 ]
        return line
    end    

    def write( data )
        """Write data to node.
           data: string"""
        File.new(@stdin.fileno(), "r+").syswrite(data)
        #os.write( @stdin.fileno(), data )
    end
        
    def terminate()
        "Send kill signal to Node and clean up after it."
        unmountPrivateDirs()
        if @shell
            if !@shell.poll()
                os.killpg( @shell.pid, signal.SIGHUP )
            end
        end        
        cleanup()
    end    

    def stop( deleteIntfs=false )
        """Stop node.
           deleteIntfs: delete interfaces? (false)"""
        if deleteIntfs
            deleteIntfs()
        end    
        terminate()
    end
        
    def waitReadable( timeoutms=nil )
        """Wait until node's output is readable.
           timeoutms: timeout in ms or nil to wait indefinitely."""
        if @readbuf.length == 0
            @pollOut.poll( timeoutms )
        end
    end

    def sendCmd( *args, kwargs )
        """Send a command, followed by a command to echo a sentinel,
           and return without waiting for the command to complete.
           args: command and arguments, or string
           printPid: print command's PID? (false)"""
        assert @shell and not @waiting
        printPid = kwargs.fetch( 'printPid', false )
        # Allow sendCmd( [ list ] )
        if args.length == 1 and args[0].is_a Array
            cmd = args[ 0 ]
        # Allow sendCmd( cmd, arg1, arg2... )
        elsif args.length  > 0
            cmd = args
        end    
        # Convert to string
        if not cmd.is_a? String
            cmd = ( [for c in cmd do c.to_s end] ).join(' ')
        end

        if not re.search( "\w".inspect, cmd )
            # Replace empty commands with something harmless
            cmd = 'echo -n'
        end
            
        @lastCmd = cmd
        # if a builtin command is backgrounded, it still yields a PID
        if cmd.length > 0 and cmd[ -1 ] == '&'
            # print ^A{pid}\n so monitor() can set lastPid
            cmd += ' printf "\\001%d\\012" $! '
        elsif printPid and not isShellBuiltin( cmd )
            cmd = 'mnexec -p ' + cmd
        end    
        write( cmd + '\n' )
        @lastPid = nil
        @waiting = true
    end 

    def sendInt( intr=3.chr )
        "Interrupt running command."
        debug( 'sendInt: writing chr(%d)\n' % ord( intr ) )
        write( intr )
    end
        
    def monitor( timeoutms=nil, findPid=true )
        """Monitor and return the output of a command.
           Set @waiting to false if command has completed.
           timeoutms: timeout in ms or nil to wait indefinitely
           findPid: look for PID from mnexec -p"""
        waitReadable( timeoutms )
        data = read( 1024 )
        pidre = "\[\d+\] \d+\r\n".inspect
        # Look for PID
        marker = 1.chr + "\d+\r\n".inspect
        
        if findPid and data.include? 1.chr
            # suppress the job and PID of a backgrounded command
            if re.findall( pidre, data )
                data = re.sub( pidre, '', data )
            end    
            # Marker can be read in chunks; continue until all of it is read
            while not re.findall( marker, data )
                data += read( 1024 )
            end    
            markers = re.findall( marker, data )
            if markers
                @lastPid = markers[ 0 ][ 1..markers[ 0 ].length ].to_i
                data = re.sub( marker, '', data )
            end    
        end        
        # Look for sentinel/EOF
        
        if data.length > 0 and data[ -1 ] == 127.chr
            @waiting = false
            data = data[0..-1]
        elsif  data.include? 127.chr
            @waiting = false
            data = data.replace( 127.chr, '' )
        end        

        return data
    end    

    def waitOutput( verbose=false, findPid=true )
        """Wait for a command to complete.
           Completion is signaled by a sentinel character, ASCII(127)
           appearing in the output stream.  Wait for the sentinel and return
           the output, including trailing newline.
           verbose: print output interactively"""
        log = if verbose 
                info 
              else 
                debug
              end   
        output = ''
        while @waiting
            data = monitor( findPid=findPid )
            output += data
            log( data )
        end    
        return output
    end    

    def cmd(*args, kwargs )
        """Send a command, wait for output, and return it.
           cmd: string"""
        verbose = kwargs.fetch( 'verbose', false )
        log = if verbose 
                info 
              else 
                debug
              end
        log( '*** %s : %s\n' % [ @name, args ] )
        if @shell
            sendCmd( *args, kwargs )
            return waitOutput( verbose )
        else
            warn( '(%s exited - ignoring cmd%s)\n' % [ self, args ] )
        end
    end 
    # to access class variable
   
        
    
    def cmdPrint(*args)
        """Call cmd and printing its output
           cmd: string"""
        return cmd( *args, { 'verbose'=> true } )
    end    

    def popen( *args, kwargs )
        """Return a Popen() object in our namespace
           args: Popen() args, single list, or string
           kwargs: Popen() keyword args"""
        defaults = { 'stdout'=> PIPE, 'stderr'=> PIPE,
                     'mncmd'=>
                     [ 'mnexec', '-da', @pid.to_s ] }
        defaults.merge!( kwargs )
        if args.length == 1
            if args[0].is_a? Array
                # popen([cmd, arg1, arg2...])
                cmd = args[ 0 ]
            elsif isinstance( args[ 0 ], basestring )
                # popen("cmd arg1 arg2...")
                cmd = args[ 0 ].split()
            else
                raise Exception( 'popen() requires a string or list' )
            end

        elsif args.length > 0
            # popen( cmd, arg1, arg2... )
            cmd = list( args )
        end
        # Attach to our namespace  using mnexec -a
        cmd = defaults.pop( 'mncmd' ) + cmd
        # Shell requires a string, not a list!
        if defaults.get( 'shell', false )
            cmd = cmd.join( ' ' )
        end    
        popen = _popen( cmd, defaults )
        return popen
    end    

    def pexec(*args, kwargs )
        """Execute a command using popen
           returns: out, err, exitcode"""
        popen = popen( *args, stdin=PIPE, stdout=PIPE, stderr=PIPE,
                            kwargs )
        # Warning: this can fail with large numbers of fds!
        out, err = popen.communicate()
        exitcode = popen.wait()
        return out, err, exitcode
    end    

    # Interface management, configuration, and routing

    # BL notes: This might be a bit redundant or over-complicated.
    # However, it does allow a bit of specialization, including
    # changing the canonical interface names. It's also tricky since
    # the real interfaces are created as veth pairs, so we can't
    # make a single interface at a time.

    def newPort( )
        "Return the next port number to allocate."
        if @ports.length > 0
            return @ports.values.max + 1
        end    
        return @@portBase
    end
        
    def addIntf( intf, port=nil, moveIntfFn=moveIntf )
        """Add an interface.
           intf: interface
           port: port number (optional, typically OpenFlow port number)
           moveIntfFn: function to move interface (optional)"""
        if port is nil
            port = newPort()
        end    
        @intfs[ port ] = intf
        @ports[ intf ] = port
        @nameToIntf[ intf.name ] = intf
        debug( '\n' )
        debug( 'added intf %s (%d) to node %s\n' % [
                intf, port, @name ] )
        if @inNamespace
            debug( 'moving', intf, 'into namespace for', @name, '\n' )
            moveIntfFn( intf.name, self  )
        end
    end        

    def defaultIntf( )
        "Return interface for lowest port"
        ports = @intfs.keys()
        if ports
            return @intfs.keys.min
        else
            warn( '*** defaultIntf: warning:', @name,
                  'has no interfaces\n' )
        end
    end

        def intf(  intf=nil )
        """Return our interface object with given string name,
           default intf if name is falsy (nil, empty string, etc).
           or the input intf arg.

        Having this fcn return its arg for Intf objects makes it
        easier to construct functions with flexible input args for
        interfaces (those that accept both string names and Intf objects).
        """
        if not intf
            return defaultIntf()
        elsif isinstance( intf, basestring)
            return @nameToIntf[ intf ]
        else
            return intf
        end
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
                    connections += [ intf, link.intf2  ]
                elsif node1 == node and node2 == self
                    connections += [ intf, link.intf1  ]
                end
            end
        end
        return connections
    end    

    def deleteIntfs(  checkName=true )
        """Delete all of our interfaces.
           checkName: only delete interfaces that contain our name"""
        # In theory the interfaces should go away after we shut down.
        # However, this takes time, so we're better off removing them
        # explicitly so that we won't get errors if we run before they
        # have been removed by the kernel. Unfortunately this is very slow,
        # at least with Linux kernels before 2.6.33
        for intf in @intfs.values()
            # Protect against deleting hardware interfaces
            if ( intf.name.include? @name ) or ( not checkName )
                intf.delete()
                info( '.' )
            end
        end        
    end            

    # Routing support

    def setARP(  ip, mac )
        """Add an ARP entry.
           ip: IP address as string
           mac: MAC address as string"""
        result = cmd( 'arp', '-s', ip, mac )
        return result
    end    

    def setHostRoute(  ip, intf )
        """Add route to host.
           ip: IP address as dotted decimal
           intf: string, interface name"""
        return cmd( 'route add -host', ip, 'dev', intf )
    end
        
    def setDefaultRoute(  intf=nil )
        """Set the default route to go through intf.
           intf: Intf or {dev <intfname> via <gw-ip> ...}"""
        # Note setParam won't call us if intf is nil
        if isinstance( intf, basestring ) and intf.include? ' '
            params = intf
        else
            params = 'dev %s' % intf
        end    
        # Do this in one line in case we're messing with the root namespace
        cmd( 'ip route del default; ip route add default', params )
    end    
    # Convenience and configuration methods

    def setMAC(  mac, intf=nil )
        """Set the MAC address for an interface.
           intf: intf or intf name
           mac: MAC address as string"""
        return intf( intf ).setMAC( mac )
    end    

    def setIP(  ip, prefixLen=8, intf=nil, kwargs )
        """Set the IP address for an interface.
           intf: intf or intf name
           ip: IP address as a string
           prefixLen: prefix length, e.g. 8 for /8 or 16M addrs
           kwargs: any additional arguments for intf.setIP"""
        return intf( intf ).setIP( ip, prefixLen, kwargs )
    end    

    def IP(  intf=nil )
        "Return IP address of a node or specific interface."
        return intf( intf ).IP()
    end    

    def MAC(  intf=nil )
        "Return MAC address of a node or specific interface."
        return intf( intf ).MAC()
    end
    def intfIsUp(  intf=nil )
        "Check if an interface is up."
        return intf( intf ).isUp()
    end
    # The reason why we configure things in this way is so
    # That the parameters can be listed and documented in
    # the config method.
    # Dealing with subclasses and superclasses is slightly
    # annoying, but at least the information is there!

    def setParam(  results, method, param )
        """Internal method: configure a *single* parameter
           results: dict of results to update
           method: config method name
           param: arg=value (ignore if value=nil)
           value may also be list or dict"""
        name, value = param.items()[ 0 ]
        if value is nil
            return
        end    
        f = getattr( self, method, nil )
        if not f
            return
        end    
        if value.is_a? Array
            result = f( *value )
        elsif value.is_a? Hash
            result = f( value )
        else
            result = f( value )
        end    
        results[ name ] = result
        return result
    end    

    def config(  mac=nil, ip=nil,
                defaultRoute=nil, lo='up', _params )
        """Configure Node according to (optional) parameters
           mac: MAC address for default interface
           ip: IP address for default interface
           ifconfig: arbitrary interface configuration
           Subclasses should override this method and call
           the parent class's config(params)"""
        # If we were overriding this method, we would call
        # the superclass config method here as follows:
        # r = Parent.config( _params )
        r = Hash.new
        setParam( r, 'setMAC', mac=mac )
        setParam( r, 'setIP', ip=ip )
        setParam( r, 'setDefaultRoute', defaultRoute=defaultRoute )
        # This should be examined
        cmd( 'ifconfig lo ' + lo )
        return r
    end    

    def configDefault(  moreParams )
        "Configure with default parameters"
        @params.merge!(moreParams)
        #@params.update( moreParams )
        config( @params )
    end
        
    # This is here for backward compatibility
    
    def linkTo(  node, link=Link )
        """(Deprecated) Link to another node
           replace with Link( node1, node2)"""
        return link( self, node )
    end
    # Other methods

    def intfList( )
        "List of our interfaces sorted by port number"
        sortedkeys=@intfs.keys()
        return [ for p in sortedkeys do @intfs[ p ] end]
    end    

    def intfNames( )
        "The names of our interfaces sorted by port number"
        return [ for i in intfList() do i.to_s end]
    end    

    def __repr__(  )
        "More informative string representation"
        intfs = ( ( [ '%s:%s' % 
                              for i in intfList() do [ i.name, i.IP() ] end] ).join(',') )
        return '<%s %s: %s pid=%s> ' % [
            self.__class__.__name__, @name, intfs, @pid ]
    end    

    def __str__( )
        "Abbreviated string representation"
        return @name
    end    
    # Automatic class setup support

    @@isSetup = false

    def self.isSetup()
        return @@isSetup
    end    

    @classmethod
    def checkSetup( cls )
        "Make sure our class and superclasses are set up"
        while cls and not getattr( cls, 'isSetup', true )
            cls.setup()
            cls.isSetup = true
            # Make pylint happy
            cls = getattr( type( cls ), '__base__', nil )
        end    
    end        

    @classmethod
    def setup( cls )
        "Make sure our class dependencies are available"
        pathCheck( 'mnexec', 'ifconfig', moduleName='Mininet')
    end

end
    
class Host < Node 
    "A host is simply a Node"
end       
