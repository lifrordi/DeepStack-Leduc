--- Computes the expected value of a strategy profile on a game's public tree,
-- as well as the value of a best response against the profile.
-- @classmod tree_values

local arguments = require 'Settings.arguments'
local constants = require 'Settings.constants'
local game_settings = require 'Settings.game_settings'
local card_tools = require 'Game.card_tools'
require 'TerminalEquity.terminal_equity'

local TreeValues = torch.class('TreeValues')

--- Constructor
function TreeValues:__init()
  self.terminal_equity = TerminalEquity()
end

--- Recursively walk the tree and calculate the probability of reaching each
-- node using the saved strategy profile.
--
-- The reach probabilities are saved in the `ranges_absolute` field of each
-- node.
-- @param node the current node of the tree
-- @param ranges_absolute a 2xK tensor containing the probabilities of each 
-- player reaching the current node with each private hand
-- @local
function TreeValues:_fill_ranges_dfs(node, ranges_absolute)
  node.ranges_absolute = ranges_absolute:clone()

  if(node.terminal) then    
    return
  end
  
  assert(node.strategy)

  local actions_count = #node.children 
  
  --check that it's a legal strategy
  local strategy_to_check = node.strategy
  
  local hands_mask = card_tools:get_possible_hand_indexes(node.board)
  
  if node.current_player ~= constants.players.chance then
    local checksum = strategy_to_check:sum(1)
    assert(not torch.any(strategy_to_check:lt(0)))
    assert(not torch.any(checksum:gt(1.001)))    
    assert(not torch.any(checksum:lt(0.999)))
    assert(not torch.any(checksum:ne(checksum)))
  end
  
  assert(node.ranges_absolute:lt(0):sum() == 0)
  assert(node.ranges_absolute:gt(1):sum() == 0)
  
  --check if the range consists only of cards that don't overlap with the board
  local impossible_hands_mask = hands_mask:clone():fill(1) - hands_mask
  local impossible_range_sum = node.ranges_absolute:clone():cmul(impossible_hands_mask:view(1, game_settings.card_count):expandAs(node.ranges_absolute)):sum()  
  assert(impossible_range_sum == 0, impossible_range_sum)
    
  local children_ranges_absolute = arguments.Tensor(#node.children, constants.players_count, game_settings.card_count)
  
  --chance player
  if node.current_player == constants.players.chance then
    --multiply ranges of both players by the chance prob
    children_ranges_absolute[{{}, constants.players.P1, {}}]:copy(node.ranges_absolute[constants.players.P1]:repeatTensor(actions_count, 1))
    children_ranges_absolute[{{}, constants.players.P2, {}}]:copy(node.ranges_absolute[constants.players.P2]:repeatTensor(actions_count, 1))
    
    children_ranges_absolute[{{}, constants.players.P1, {}}]:cmul(node.strategy)
    children_ranges_absolute[{{}, constants.players.P2, {}}]:cmul(node.strategy)
  --player
  else
    --copy the range for the non-acting player  
    children_ranges_absolute[{{}, 3-node.current_player, {}}] = node.ranges_absolute[3-node.current_player]:clone():repeatTensor(actions_count, 1) 
    
    --multiply the range for the acting player using his strategy    
    local ranges_mul_matrix = node.ranges_absolute[node.current_player]:repeatTensor(actions_count, 1) 
    children_ranges_absolute[{{}, node.current_player, {}}] = torch.cmul(node.strategy, ranges_mul_matrix)
  end
  
  --fill the ranges for the children
  for i = 1,#node.children do
    local child_node = node.children[i]
    local child_range = children_ranges_absolute[i]
    
    --go deeper
    self:_fill_ranges_dfs(child_node, child_range)
  end
end 

--- Recursively calculate the counterfactual values for each player at each
-- node of the tree using the saved strategy profile.
--
-- The cfvs for each player in the given strategy profile when playing against
-- each other is stored in the `cf_values` field for each node. The cfvs for
-- a best response against each player in the profile are stored in the 
-- `cf_values_br` field for each node.
-- @param node the current node
-- @local
function TreeValues:_compute_values_dfs(node)

  --compute values using terminal_equity in terminal nodes
  if(node.terminal) then
  
    assert(node.type == constants.node_types.terminal_fold or node.type == constants.node_types.terminal_call)
  
    self.terminal_equity:set_board(node.board)    
    
    local values = node.ranges_absolute:clone():fill(0)

    if(node.type == constants.node_types.terminal_fold) then
      self.terminal_equity:tree_node_fold_value(node.ranges_absolute, values, 3-node.current_player)
    else 
      self.terminal_equity:tree_node_call_value(node.ranges_absolute, values)
    end

    --multiply by the pot
    values = values * node.pot

    node.cf_values = values:viewAs(node.ranges_absolute)
    node.cf_values_br = values:viewAs(node.ranges_absolute)
  else

    local actions_count = #node.children
    local ranges_size = node.ranges_absolute:size(2)

    --[[actions, players, ranges]]
    local cf_values_allactions = arguments.Tensor(#node.children, 2, ranges_size):fill(0)
    local cf_values_br_allactions = arguments.Tensor(#node.children, 2, ranges_size):fill(0)

    for i = 1,#node.children do    
      local child_node = node.children[i]
      self:_compute_values_dfs(child_node)
      cf_values_allactions[i] = child_node.cf_values
      cf_values_br_allactions[i] = child_node.cf_values_br
    end

    node.cf_values = arguments.Tensor(2, ranges_size):fill(0)
    node.cf_values_br = arguments.Tensor(2, ranges_size):fill(0)

    --strategy = [[actions x range]]
    local strategy_mul_matrix = node.strategy:viewAs(arguments.Tensor(actions_count, ranges_size))

    --compute CFVs given the current strategy for this node
    if node.current_player == constants.players.chance then
      node.cf_values = cf_values_allactions:sum(1)[1]
      node.cf_values_br = cf_values_br_allactions:sum(1)[1]
    else
      node.cf_values[node.current_player] = torch.cmul(strategy_mul_matrix, cf_values_allactions[{{}, node.current_player, {}}]):sum(1)
      node.cf_values[3-node.current_player] = (cf_values_allactions[{{}, 3-node.current_player, {}}]):sum(1)
  
      --compute CFVs given the BR strategy for this node
      node.cf_values_br[3 - node.current_player] = cf_values_br_allactions[{{}, 3 - node.current_player, {}}]:sum(1)
      node.cf_values_br[node.current_player] = cf_values_br_allactions[{{}, node.current_player, {}}]:max(1)
    end
  end

  --counterfactual values weighted by the reach prob
  node.cfv_infset = arguments.Tensor(2)
  node.cfv_infset[1] = node.cf_values[1] * node.ranges_absolute[1]
  node.cfv_infset[2] = node.cf_values[2] * node.ranges_absolute[2]

  --compute CFV-BR values weighted by the reach prob
  node.cfv_br_infset = arguments.Tensor(2)
  node.cfv_br_infset[1] = node.cf_values_br[1] * node.ranges_absolute[1]
  node.cfv_br_infset[2] = node.cf_values_br[2] * node.ranges_absolute[2]

  node.epsilon = node.cfv_br_infset - node.cfv_infset
  node.exploitability = node.epsilon:mean()
end                                        

--- Compute the self play and best response values of a strategy profile on
-- the given game tree.
-- 
-- The cfvs for each player in the given strategy profile when playing against
-- each other is stored in the `cf_values` field for each node. The cfvs for
-- a best response against each player in the profile are stored in the 
-- `cf_values_br` field for each node.
--
-- @param root The root of the game tree. Each node of the tree is assumed to
-- have a strategy saved in the `strategy` field.
-- @param[opt] starting_ranges probability vectors over player private hands
-- at the root node (default uniform)
function TreeValues:compute_values( root, starting_ranges )
  
  --1.0 set the starting range
  local uniform_ranges = arguments.Tensor(constants.players_count, game_settings.card_count):fill(1.0/game_settings.card_count)  
  local starting_ranges = starting_ranges or uniform_ranges
  
  --2.0 check the starting ranges
  local checksum = starting_ranges:sum(2)[{{}, 1}]
  assert(math.abs(checksum[1] - 1) < 0.0001, 'starting range does not sum to 1')
  assert(math.abs(checksum[2] - 1) < 0.0001, 'starting range does not sum to 1')
  assert(starting_ranges:lt(0):sum() == 0) 
  
  --3.0 compute the values  
  self:_fill_ranges_dfs(root, starting_ranges)
  self:_compute_values_dfs(root)
end
