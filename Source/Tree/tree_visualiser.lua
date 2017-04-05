--- Generates visual representations of game trees.
-- @classmod tree_visualiser
local TreeVisualiser = torch.class('TreeVisualiser')
local arguments = require 'Settings.arguments'
local constants = require 'Settings.constants'
local card_to_string = require 'Game.card_to_string_conversion'

--TODO: README
--dot tree_2.dot -Tpng -O

--- Constructor
function TreeVisualiser:__init()
    self.node_to_graphviz_counter = 0
    self.edge_to_graphviz_counter = 0
end

--- Generates a string representation of a tensor.
-- @param tensor a tensor
-- @param[opt] name a name for the tensor
-- @param[opt] format a format string to use with @{string.format} for each
-- element of the tensor
-- @param[opt] labels a list of labels for the elements of the tensor
-- @return a string representation of the tensor
-- @local
function TreeVisualiser:add_tensor(tensor, name, format, labels)
  
  local out = ''
  if name then
    out = '| ' .. name .. ': '
  end
  
  if not format then
    format = "%.3f"
  end

  for i = 1,tensor:size(1) do
    if labels then
      out = out .. labels[i] .. ":"
    end
    out = out .. string.format(format, tensor[i]) .. ", " 
  end
  
  return out
end

--- Generates a string representation of any range or value fields that are set
-- for the given tree node.
-- @param node the node
-- @return a string containing concatenated representations of any tensors
-- stored in the `ranges_absolute`, `cf_values`, or `cf_values_br` fields of
-- the node.
-- @local
function TreeVisualiser:add_range_info(node)   
  local out = ""
  
  if(node.ranges_absolute) then 
    out = out .. self:add_tensor(node.ranges_absolute[1], 'abs_range1')
    out = out .. self:add_tensor(node.ranges_absolute[2], 'abs_range2')
  end

  if(node.cf_values) then
    --cf values computed by real tree dfs
    out = out .. self:add_tensor(node.cf_values[1], 'cf_values1')
    out = out .. self:add_tensor(node.cf_values[2], 'cf_values2')
  end
  
  if(node.cf_values_br) then
    --cf values that br has in real tree
    out = out .. self:add_tensor(node.cf_values_br[1], 'cf_values_br1')
    out = out .. self:add_tensor(node.cf_values_br[2], 'cf_values_br2')
  end
  
  return out
end

--- Generates data for a graphical representation of a node in a public tree.
-- @param node the node to generate data for
-- @return a table containing `name`, `label`, and `shape` fields for graphviz
-- @local
function TreeVisualiser:node_to_graphviz(node)   
  local out = {}
  
  --1.0 label
  out.label = '"<f0>' .. node.current_player
  
  if node.terminal then
    if node.type == constants.node_types.terminal_fold then
      out.label = out.label .. '| TERMINAL FOLD'
    elseif node.type == constants.node_types.terminal_call then
      out.label = out.label .. '| TERMINAL CALL'
    else
      assert('unknown terminal node type')
    end  
  else
    out.label = out.label .. '| bet1: ' .. node.bets[constants.players.P1] .. '| bet2: ' .. node.bets[constants.players.P2]
    
    if node.street then
      out.label = out.label .. '| street: ' .. node.street
      out.label = out.label .. '| board: ' .. card_to_string:cards_to_string(node.board)
      out.label = out.label .. '| depth: ' .. node.depth
    end 
  end
  
  if node.margin then
    out.label = out.label ..  '| margin: ' .. node.margin
  end  

  out.label = out.label .. self:add_range_info(node)  
  
  if(node.cfv_infset) then
    out.label = out.label ..  '| cfv1: ' .. node.cfv_infset[1]
    out.label = out.label ..  '| cfv2: ' .. node.cfv_infset[2]
    out.label = out.label ..  '| cfv_br1: ' .. node.cfv_br_infset[1]
    out.label = out.label ..  '| cfv_br2: ' .. node.cfv_br_infset[2]
    out.label = out.label ..  '| epsilon1: ' .. node.epsilon[1]
    out.label = out.label ..  '| epsilon2: ' .. node.epsilon[2]    
  end
  
  if node.lookahead_coordinates then
    out.label = out.label ..  '| COORDINATES '
    out.label = out.label ..  '| action_id: ' .. node.lookahead_coordinates[1]
    out.label = out.label ..  '| parent_action_id: ' .. node.lookahead_coordinates[2]
    out.label = out.label ..  '| gp_id: ' .. node.lookahead_coordinates[3]
  end
  
  out.label = out.label .. '"'
  
  --2.0 name
  out.name = '"node' .. self.node_to_graphviz_counter .. '"'
  
  --3.0 shape
  out.shape = '"record"' 
    
  self.node_to_graphviz_counter = self.node_to_graphviz_counter + 1
  return out
end  

--- Generates data for graphical representation of a public tree action as an
-- edge in a tree.
-- @param from the graphical node the edge comes from
-- @param to the graphical node the edge goes to
-- @param node the public tree node before at which the action is taken
-- @param child_node the public tree node that results from taking the action
-- @return a table containing fields `id_from`, `id_to`, `id` for graphviz and
-- a `strategy` field to use as a label for the edge
-- @local
function TreeVisualiser:nodes_to_graphviz_edge(from, to, node, child_node)
  local out = {}
  
  out.id_from = from.name
  out.id_to = to.name
  out.id = self.edge_to_graphviz_counter
  
  --get the child id of the child node
  local child_id = -1
  for i=1,#node.children do
    if node.children[i] == child_node then
      child_id = i
    end
  end
  
  assert(child_id ~= -1)
  out.strategy = self:add_tensor(node.strategy[child_id], nil, "%.2f", card_to_string.card_to_string_table)
  
  self.edge_to_graphviz_counter = self.edge_to_graphviz_counter + 1
  return out
end  

--- Recursively generates graphviz data from a public tree.
-- @param node the current node in the public tree
-- @param nodes a table of graphical nodes generated so far
-- @param edges a table of graphical edges generated so far
-- @local
function TreeVisualiser:graphviz_dfs(node, nodes, edges)

  local gv_node = self:node_to_graphviz(node)
  table.insert(nodes, gv_node)
  
  for i = 1,#node.children do
    local child_node = node.children[i]
    local gv_node_child = self:graphviz_dfs(child_node, nodes, edges)
    local gv_edge = self:nodes_to_graphviz_edge(gv_node, gv_node_child, node, child_node)
    table.insert(edges, gv_edge)
  end

  return gv_node
end

--- Generates `.dot` and `.svg` image files which graphically represent 
-- a game's public tree.
-- 
-- Each node in the image lists the acting player, the number of chips
-- committed by each player, the current betting round, public cards,
-- and the depth of the subtree after the node, as well as any probabilities
-- or values stored in the `ranges_absolute`, `cf_values`, or `cf_values_br`
-- fields of the node.
-- 
-- Each edge in the image lists the probability of the action being taken
-- with each private card.
--
-- @param root the root of the game's public tree
-- @param filename a name used for the output files
function TreeVisualiser:graphviz(root, filename)
  filename = filename or 'tree_2.dot'
  local out = 'digraph g {  graph [ rankdir = "LR"];node [fontsize = "16" shape = "ellipse"]; edge [];'
    
  local nodes = {}
  local edges = {}
  self:graphviz_dfs(root, nodes, edges)
    
  for i = 1, #nodes do
    local node = nodes[i]
    local node_text = node.name .. '[' .. 'label=' .. node.label .. ' shape = ' .. node.shape .. '];'
      
    out = out .. node_text
  end
      
  for i = 1, #edges do
    local edge = edges[i]
    local edge_text = edge.id_from .. ':f0 -> ' .. edge.id_to .. ':f0 [ id = ' .. edge.id .. ' label = "' .. edge.strategy .. '"];'
      
    out = out .. edge_text
  end
    
  out = out .. '}'
    
  --write into dot file
  local file = io.open (arguments.data_directory .. 'Dot/' .. filename, 'w')
  file:write(out)
  file:close()
  
  --run graphviz program to generate image
  os.execute( 'dot ' .. arguments.data_directory .. 'Dot/' .. filename .. ' -Tsvg -O')
end