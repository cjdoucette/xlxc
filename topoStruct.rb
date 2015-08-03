
class Graph
  "Build structure of topology"
  attr_reader :node
  attr_reader :edge
  def initialize
    @node = {}
    @edge = {}
  end
  
  def add_node(node, switch)
    """Add node to graph"""
    @node[node]={}
    if switch
      tmp = {'isSwitch'=>true}
      @node[node].merge!(tmp)
    end  
  end  

  def add_edge(src, dst, attr_dict=nil, *attributes)
    """Add edge to graph
       attr_dict: optional attribute dict
       attrs: more attributes
       warning: udpates attr_dict with attrs"""
    attrs = case attributes.last
    when Hash then attributes.pop
    else {}
    end
    attr_dict = if !attr_dict
                  {} 
                else 
                  attr_dict
                end
    attr_dict.merge!( attrs )

    if !@node.has_key?(src)
      @node[src] = {}
    end
    if !@node.has_key?(dst)
      @node[dst] = {}
    end  
    if !@edge.has_key?([src, dst])
      @edge[src+"-"+dst] = {}
    end  
  end  

  def assignDepth()
    
    for node in nodes()
      flag = 0
    
      for src,dst in edges
        if src == node
          flag = 1
          break
        end
      end

      if flag == 0 && !@node[node].has_key?('visited')
        tmp = {'depth'=> 0,'parent'=> nil,'visited'=>true}
        @node[node].merge!(tmp)
        subTreeDepth(node)
      end 
    end          

  end  

  def subTreeDepth(node)
    for src,dst in edges
      if dst == node && !@node[src].has_key?('visited')
        tmp = {'depth' => (@node[dst]['depth'])+1, 'parent' => node, 'visited'=>true}   
        @node[src].merge!(tmp)
        subTreeDepth(src)
      end
    end      
  end  
  
  def nodes()
    """Return list of graph nodes
       data: return list of ( node, attrs)"""
    return @node.keys()  
  end
    
  def edges()
    edg=[]
    for key in @edge.keys       
      x = key.split('-')
      src = x[0]    
      dst = x[1]
      tmp = [src, dst]
      edg.push(tmp)
    end
    return edg
  end    
  
  def printGraph()
    puts @node
  end

  def __len__()
    "Return the number of nodes"
    return @node.length
  end
end

class Topo
  "Data center network representation for structured multi-trees."
  def initialize(*args)
    """Topo object
       calls build()"""
    @graph = Graph.new()
    # ports[src][dst][sport] is port on dst that connects to src
    @ports = {}
    build( *args)
  end  

  def build( *args)
    pass
  end
    
  def addNode( name, switch=false )
    """Add Node to graph.
       returns: node name"""
    @graph.add_node( name, switch )
    return name
  end  

  def addHost( name, *opts )
    """Convenience method: Add host to graph.
       returns: host name"""  
    return addNode( name )
  end  
  
  def addSwitch( name, *opts )
    """Convenience method: Add switch to graph.
       returns: switch name"""
    result = addNode( name, true )
    return result
  end
    
  def addLink( node1, node2, *opts )
    """node1, node2: nodes to link together
       returns: link info key"""
    opts = {}
    @graph.add_edge(node1, node2, opts )
  end
    
  def nodes()
    return @graph.nodes()
  end
    
    
  def switches()
    """Return switchs.
       returns: list of switchs"""
    switchlist = [] 
    for n in nodes()  
      if isSwitch(n)
        switchlist.push(n)
      end
    end  
    #puts switchlist
    return switchlist
  end
    
  def hosts()
    """Return hosts.
       returns: list of hosts"""
    hostlist = [] 
    for n in nodes()  
      if !isSwitch(n)
        hostlist.push(n)
      end
    end  
    #puts hostlist
    return hostlist
  end

  def isSwitch(n)
        "Returns true if node is a switch."
    return @graph.node[n].fetch( 'isSwitch', false )
  end
        
  def links()
    return @graph.edges  
  end

  def hsLinks()
    hstswt=[]
    for src, dst in links
      if !isSwitch(src) && isSwitch(dst) 
        hstswt.push(src, dst)
      end        
    end
    return hstswt  
  end  

  def switchLinks()
    lnks=[]
    for src, dst in links
      if isSwitch(src) && isSwitch(dst) 
        lnks.push(src, dst)
      end        
    end
    return lnks  
  end  

  def printGraph()
    @graph.printGraph()
  end 
  def assignDepth()
    @graph.assignDepth()
  end  
  # This legacy port managefment mechanism is clunky and will probably
  # be removed at some point  
  def nodeInfo(name)
    "Return metadata (dict) for node"
    return @graph.node[name]
  end  
# Our idiom defines additional parameters in build(param...)
# pylint: disable=arguments-differ
end

class SingleSwitchTopo < Topo
  "Single switch connected to k hosts."
  def build( k=2, *opts )
    "k: number of hosts"
    @k = k
    switch = addSwitch( 's1' )
    for h in  1..k
      host = addHost( 'h%s' % h )
      addLink( host, switch )
    end  
  end    
end   

class TreeTopo < Topo 
  "Topology for a tree network with a given depth and fanout."

  def build( depth=1, fanout=2)
    # Numbering:  h1..N, s1..M
    @hostNum = 1
    @switchNum = 1
    # Build topology
    addTree( depth, fanout )
  end
    
  def addTree( depth, fanout )
    """Add a subtree starting with node n.
       returns: last node added"""
    isSwitch = depth > 0
    if isSwitch
      node = addSwitch( 's%s' % @switchNum )
      @switchNum += 1
      for i in 1..fanout
        child = addTree( depth - 1, fanout )
        addLink( child,node )
      end 
    else
      node = addHost( 'h%s' % @hostNum )
      @hostNum += 1
    end      
    return node
  end  
end    

buildtopo = TreeTopo.new(3,2)
buildtopo.assignDepth()
buildtopo.printGraph