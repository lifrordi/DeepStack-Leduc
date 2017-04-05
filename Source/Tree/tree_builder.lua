--- Builds a public tree for Leduc Hold'em or variants.
-- 
-- Each node of the tree contains the following fields:
-- 
-- * `node_type`: an element of @{constants.node_types} (if applicable)
-- 
-- * `street`: the current betting round
-- 
-- * `board`: a possibly empty vector of board cards
-- 
-- * `board_string`: a string representation of the board cards
-- 
-- * `current_player`: the player acting at the node
-- 
-- * `bets`: the number of chips that each player has committed to the pot
--
-- * `pot`: half the pot size, equal to the smaller number in `bets`
--
-- * `children`: a list of children nodes
-- @classmod tree_builder

local math = require 'math'
local arguments = require 'Settings.arguments'
local constants = require 'Settings.constants'
local card_tools = require 'Game.card_tools'
local card_to_string = require 'Game.card_to_string_conversion'
require 'Tree.strategy_filling'
require 'Game.bet_sizing'

local PokerTreeBuilder = torch.class('PokerTreeBuilder')

--- Constructor
function PokerTreeBuilder:__init()
end

--- Creates the child node after a call which transitions between betting 
-- rounds.
-- @param parent_node the node at which the transition call happens
-- @return a list containing the child node
-- @local
function PokerTreeBuilder:_get_children_nodes_transition_call(parent_node)

  local chance_node = {}
  chance_node.node_type = constants.node_types.chance_node
  chance_node.street = parent_node.street
  chance_node.board = parent_node.board
  chance_node.board_string = parent_node.board_string
  chance_node.current_player = constants.players.chance  
  chance_node.bets = parent_node.bets:clone()

  return {chance_node}
end

--- Creates the children nodes after a chance node.
-- @param parent_node the chance node
-- @return a list of children nodes
-- @local
function PokerTreeBuilder:_get_children_nodes_chance_node(parent_node)
  assert(parent_node.current_player == constants.players.chance)
  
  if self.limit_to_street then
    return {}
  end

  local next_boards = card_tools:get_second_round_boards()
  local next_boards_count = next_boards:size(1)

  local subtree_height = -1
  local children = {}

  --1.0 iterate over the next possible boards to build the corresponding subtrees
  for i=1,next_boards_count do
    local next_board = next_boards[i]
    local next_board_string = card_to_string:cards_to_string(next_board)

    local child = {}

    child.node_type = constants.node_types.inner_node
    child.parent = parent_node
    child.current_player = constants.players.P1
    child.street = parent_node.street + 1
    child.board = next_board
    child.board_string = next_board_string
    child.bets = parent_node.bets:clone()

    table.insert(children, child)
  end

  return children
end

--- Fills in additional convenience attributes which only depend on existing
-- node attributes.
-- @param node the node
-- @local
function PokerTreeBuilder:_fill_additional_attributes(node)  
  node.pot = node.bets:min()
end

--- Creates the children nodes after a player node.
-- @param parent_node the chance node
-- @return a list of children nodes
-- @local
function PokerTreeBuilder:_get_children_player_node(parent_node)
  assert(parent_node.current_player ~= constants.players.chance)

  local children = {}
  
  --1.0 fold action
  local fold_node = {}
  fold_node.type = constants.node_types.terminal_fold
  fold_node.terminal = true
  fold_node.current_player = 3 - parent_node.current_player
  fold_node.street = parent_node.street 
  fold_node.board = parent_node.board
  fold_node.board_string = parent_node.board_string
  fold_node.bets = parent_node.bets:clone()
  table.insert(children, fold_node)
  
  --2.0 check action
  if parent_node.current_player == constants.players.P1 and (parent_node.bets[1] == parent_node.bets[2]) then
    local check_node = {}
    check_node.type = constants.node_types.check
    check_node.terminal = false
    check_node.current_player = 3 - parent_node.current_player
    check_node.street = parent_node.street 
    check_node.board = parent_node.board
    check_node.board_string = parent_node.board_string
    check_node.bets = parent_node.bets:clone()
    table.insert(children, check_node)
  --transition call
  elseif parent_node.street == 1 and ( (parent_node.current_player == constants.players.P2 and parent_node.bets[1] == parent_node.bets[2]) or (parent_node.bets[1] ~= parent_node.bets[2] and parent_node.bets:max() < arguments.stack) ) then 
    local chance_node = {}
    chance_node.node_type = constants.node_types.chance_node
    chance_node.street = parent_node.street
    chance_node.board = parent_node.board
    chance_node.board_string = parent_node.board_string
    chance_node.current_player = constants.players.chance  
    chance_node.bets = parent_node.bets:clone():fill(parent_node.bets:max())
    table.insert(children, chance_node)
  else
  --2.0 terminal call - either last street or allin
    local terminal_call_node = {}
    terminal_call_node.type = constants.node_types.terminal_call
    terminal_call_node.terminal = true
    terminal_call_node.current_player = 3 - parent_node.current_player
    terminal_call_node.street = parent_node.street 
    terminal_call_node.board = parent_node.board
    terminal_call_node.board_string = parent_node.board_string
    terminal_call_node.bets = parent_node.bets:clone():fill(parent_node.bets:max())
    table.insert(children, terminal_call_node)
  end

  --3.0 bet actions    
  local possible_bets = self.bet_sizing:get_possible_bets(parent_node)
  
  if possible_bets:dim() ~= 0 then
    assert(possible_bets:size(2) == 2)
    
    for i=1, possible_bets:size(1) do
      local child = {}
      child.parent = parent_node
      child.current_player = 3 - parent_node.current_player
      child.street = parent_node.street 
      child.board = parent_node.board
      child.board_string = parent_node.board_string
      child.bets = possible_bets[i]
      table.insert(children, child)
    end
  end
  
  return children
end

--- Creates the children after a node.
-- @param parent_node the node to create children for
-- @return a list of children nodes
-- @local
function PokerTreeBuilder:_get_children_nodes(parent_node)

  --is this a transition call node (leading to a chance node)?
  local call_is_transit = parent_node.current_player == constants.players.P2 and parent_node.bets[1] == parent_node.bets[2] and parent_node.street < constants.streets_count
  
  local chance_node = parent_node.current_player == constants.players.chance
  --transition call -> create a chance node
  if parent_node.terminal then
    return {}
  --chance node
  elseif chance_node then
    return self:_get_children_nodes_chance_node(parent_node)
  --inner nodes -> handle bet sizes
  else
    return self:_get_children_player_node(parent_node)
  end

  assert(false)
end

--- Recursively build the (sub)tree rooted at the current node.
-- @param current_node the root to build the (sub)tree from
-- @return `current_node` after the (sub)tree has been built
-- @local
function PokerTreeBuilder:_build_tree_dfs(current_node)
  
  self:_fill_additional_attributes(current_node)
  local children = self:_get_children_nodes(current_node)
  current_node.children = children
  
  local depth = 0

  current_node.actions = arguments.Tensor(#children)
  for i=1,#children do    
    children[i].parent = current_node
    self:_build_tree_dfs(children[i])
    depth = math.max(depth, children[i].depth)
    
    if i == 1 then
      current_node.actions[i] = constants.actions.fold
    elseif i == 2 then
      current_node.actions[i] = constants.actions.ccall
    else  
      current_node.actions[i] = children[i].bets:max()
    end
  end
  
  current_node.depth = depth + 1
  
  return current_node
end

--- Builds the tree.
-- @param params table of tree parameters, containing the following fields:
-- 
-- * `street`: the betting round of the root node
-- 
-- * `bets`: the number of chips committed at the root node by each player
-- 
-- * `current_player`: the acting player at the root node
-- 
-- * `board`: a possibly empty vector of board cards at the root node
-- 
-- * `limit_to_street`: if `true`, only build the current betting round
-- 
-- * `bet_sizing` (optional): a @{bet_sizing} object which gives the allowed
-- bets for each player 
-- @return the root node of the built tree
function PokerTreeBuilder:build_tree(params)
  local root = {}
  --copy necessary stuff from the root_node not to touch the input
  root.street = params.root_node.street
  root.bets = params.root_node.bets:clone()
  root.current_player = params.root_node.current_player
  root.board = params.root_node.board:clone()
  
  params.bet_sizing = params.bet_sizing or BetSizing(arguments.Tensor(arguments.bet_sizing))

  assert(params.bet_sizing)

  self.bet_sizing = params.bet_sizing
  self.limit_to_street = params.limit_to_street

  self:_build_tree_dfs(root)
  
  local strategy_filling = StrategyFilling()
  strategy_filling:fill_uniform(root)
  
  return root
end
