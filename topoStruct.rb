
class Graph
  "Build structure of topology"
  def initialize
    @node = {}
    @edge = {}
  end
  
  def add_node(node, attr_dict=nil, *attributes)
    """Add node to graph
       attr_dict: attribute dict (optional)
       attrs: more attributes (optional)
       warning: updates attr_dict with attrs"""
    attrs = case attributes.last
    when Hash then attributes.pop
    else {}
    end
    if !attr_dict
      attr_dict = {} 
    end  
    attr_dict.merge!(attrs)
    @node[node] = attr_dict
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
      if flag == 0
        tmp = {'depth'=> 0,'parent'=> nil}
        @node[node].merge!(tmp)
        subTreeDepth(node)
      end  
    end          

  end  

  def subTreeDepth(node)
    for src,dst in edges
      if dst == node
        tmp = {'depth' => (@node[dst]['depth'])+1, 'parent' => node}   
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
    edges=[]
    for key in @edge.keys       
      x = key.split('-')
      src = x[0]    
      dst = x[1]
      tmp = [src, dst]
    end
    edges.push(tmp)
    return edges
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
    params = case args.last
    when Hash then args.pop
    else {}
    end   
    
    """Topo object.
       Optional named parameters:
       hinfo: default host options
       sopts: default switch options
       lopts: default link options
       calls build()"""
    @graph = Graph.new()
    #@hopts = params.pop( 'hopts', {} )
    #@sopts = params.pop( 'sopts', {} )
    #@lopts = params.pop( 'lopts', {} )
    # ports[src][dst][sport] is port on dst that connects to src
    @ports = {}
    build( *args)
  end  

  def build( *args)
    pass
  end
    
  def addNode( name, *opts )
    """Add Node to graph.
       name: name
       opts: node options
       returns: node name"""
       opts = {}
    @graph.add_node( name, opts )
    return name
  end  

  def addHost( name, *opts )
    """Convenience method: Add host to graph.
       name: host name
       opts: host options
       returns: host name"""  
    return addNode( name, opts )
  end  
  
  def addSwitch( name, *opts )
    """Convenience method: Add switch to graph.
       name: switch name
       opts: switch options
       returns: switch name"""
    
    result = addNode( name, opts )
    return result
  end
    
  def addLink( node1, node2, *opts )
    """node1, node2: nodes to link together
       opts: link options (optional)
       returns: link info key"""
    opts = {}
    @graph.add_edge(node1, node2, opts )
  end
    
  def nodes()
    return @graph.nodes()
  end
    
  def isSwitch(n)
    "Returns true if node is a switch."
    return @graph.node[n].fetch('isSwitch', false)
  end
    
  def switches()
    return  [for n in nodes() do 
              if isSwitch(n) 
                n 
              end 
            end]  
  end
    
  def hosts()
    """Return hosts.
       returns: list of hosts"""
    return [for n in nodes() do 
              if !isSwitch(n) 
                n 
              end 
            end]
  end

  def links()
    for src, dst in @graph.edges()
      yield(src, dst)
    end  
  end

  def hslinks()
    for src, dst in links
      if !isSwitch(src) 
        yield(src, dst)
      end        
    end  
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

class SingleSwitchReversedTopo < Topo 

  def build( k=2 )
    "k: number of hosts"
    @k = k
    switch = addSwitch( 's1' )
    for h in 1..k
      host = addHost( 'h%s' % h )
      addLink( host, switch )
    end
  end

end      


class MinimalTopo < SingleSwitchTopo 
  "Minimal topology with two hosts and one switch"
  def build()
    return SingleSwitchTopo.build( k=2 )
  end
end    

buildtopo = SingleSwitchTopo.new()
buildtopo.assignDepth()
buildtopo.printGraph()