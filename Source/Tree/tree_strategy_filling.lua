--- Recursively performs continual re-solving at every node of a public tree to
-- generate the DeepStack strategy for the entire game.
-- 
-- A strategy is represented at each public node by a NxK tensor where:
-- 
-- * N is the number of possible child nodes.
-- 
-- * K is the number of information sets for the active player in the public 
-- node. For the Leduc Hold'em variants we implement, there is one for each
-- private card that the player could hold.
-- 
-- For a player node, `strategy[i][j]` gives the probability of taking the
-- action  that leads to the `i`th child when the player holds the `j`th card.
-- 
-- For a chance node, `strategy[i][j]` gives the probability of reaching the
-- `i`th child for either player when that player holds the `j`th card.
-- @classmod tree_strategy_filling

require 'math'
local arguments = require 'Settings.arguments'
local card_tools = require 'Game.card_tools'
local constants = require 'Settings.constants'
local game_settings = require 'Settings.game_settings'
require 'Lookahead.mock_resolving'
require 'Lookahead.resolving'

local TreeStrategyFilling = torch.class('TreeStrategyFilling')

--- Constructor
function TreeStrategyFilling:__init()
  self.board_count = card_tools:get_boards_count()
end

--- Fills all chance nodes of a subtree with the probability of each outcome.
-- @param node the root of the subtree
-- @local
function TreeStrategyFilling:_fill_chance(node)
  if(node.terminal) then
    return
  end
  if node.current_player == constants.players.chance then --chance node, we will fill uniform strategy 
    --works only for chance node at start of second round
    assert(#node.children == self.board_count)
    --filling strategy
    --we will fill strategy with an uniform probability, but it has to be zero for hands that are not possible on
    --corresponding board
    node.strategy = arguments.Tensor(#node.children, game_settings.card_count):fill(0)
    --setting strategy for impossible hands to 0
    for i = 1,#node.children do
      local child_node = node.children[i]
      local mask = card_tools:get_possible_hand_indexes(child_node.board):byte()
      node.strategy[i][mask] = 1.0/(self.board_count - 2)
    end
  end

  for i = 1,#node.children do
    local child_node = node.children[i]
    self:_fill_chance(child_node)
  end
end

--- Recursively fills a subtree with a uniform random strategy for the given
--  player.
-- 
-- Used in sections of the game to which the player doesn't play.
--
-- @param node the root of the subtree
-- @param player the player which is given the uniform random strategy
-- @local
function TreeStrategyFilling:_fill_uniformly(node, player)
  if(node.terminal) then
    return
  end
  if node.current_player == player then
    --fill uniform strategy
    node.strategy = arguments.Tensor(#node.children, game_settings.card_count):fill(1.0 / #node.children)
  end

  for i = 1,#node.children do
    local child_node = node.children[i]
    self:_fill_uniformly(child_node, player)
  end
end

--- Recursively fills a player's strategy for the subtree rooted at an 
-- opponent node.
-- 
-- @param params tree walk parameters (see @{_fill_strategies_dfs})
-- @local
function TreeStrategyFilling:_process_opponent_node(params)
  --  node, player, range, cf_values, strategy_computation, our_last_action
  local node = params.node
  local player = params.player
  local range = params.range
  local cf_values = params.cf_values
  local resolving = params.resolving
  local our_last_action = params.our_last_action

  assert(not node.terminal and node.current_player ~= player)
  
  --when opponent plays, we will do nothing except sending cf_values to the child nodes
  for i = 1,#node.children do
    local child_node = node.children[i]
    if not child_node.terminal then
      local child_params = {}
      child_params.node = child_node
      child_params.range = range
      child_params.player = player
      child_params.cf_values = cf_values
      child_params.resolving = params.resolving
      child_params.our_last_action = our_last_action

      self:_fill_strategies_dfs(child_params)
    end
  end
end

--- Recursively fills a player's strategy in a tree.
-- 
-- @param node the root of the tree
-- @param player the player to calculate a strategy for
-- @param p1_range a probability vector of the first player's private hand 
-- at the root
-- @param p2_range a probability vector of the second player's private hand
-- at the root
-- @local
function TreeStrategyFilling:_fill_starting_node(node, player, p1_range, p2_range)

  assert(not node.terminal)
  assert(node.current_player == constants.players.P1)

  --re-solving the node
  local resolving = Resolving()
  resolving:resolve_first_node(node, p1_range, p2_range)
  --check which player plays first
  if node.current_player == player then
    self:_fill_computed_node(node, player, p1_range, resolving)
  else
    --opponent plays in this node. we need only cf-values at the beginning and we will just copy them
    local cf_values = resolving:get_root_cfv()
    local child_params = {}
    child_params.node = node
    child_params.range = p2_range
    child_params.player = player
    child_params.cf_values = cf_values
    self:_process_opponent_node(child_params)
  end
end

--- Recursively fills a player's strategy for the subtree rooted at a 
-- player node.
--
-- Re-solves to generate a strategy for the player node.
-- 
-- @param params tree walk parameters (see @{_fill_strategies_dfs})
-- @local
function TreeStrategyFilling:_fill_player_node(params)
  local node = params.node
  local player = params.player
  local range = params.range
  local cf_values = params.cf_values
  local opponent_range = params.opponent_range
  assert(not node.terminal and node.current_player == player)
  --now player plays, we have to compute his strategy
  local resolving = Resolving()
  resolving:resolve(node, range, cf_values)
  --we will send opponent range to adjust range also in our second action in the street 
  self:_fill_computed_node(node, player, range, resolving)
end

--- Recursively fills a player's strategy for the subtree rooted at a 
-- player node.
-- 
-- @param node the player node
-- @param player the player to fill the strategy for
-- @param range a probability vector giving the player's range at the node
-- @param resolving a @{resolving|Resolving} object which has been used to
-- re-solve the node
-- @local
function TreeStrategyFilling:_fill_computed_node(node, player, range, resolving)

  assert(resolving)
  assert(node.current_player == player)
  local player_actions = resolving:get_possible_actions()

  local actions_count = #node.children
  assert(actions_count == node.actions:size(1))

  --find which bets are used by player
  local used_bets = torch.ByteTensor(actions_count):zero()
  for i = 1, player_actions:size(1) do
    local player_action = player_actions[i]
    local bet_indicator = torch.eq(node.actions, player_action)
    --there has to be exactly one equivalent bet
    assert(bet_indicator:sum(1)[1] == 1)
    used_bets:add(bet_indicator:typeAs(used_bets))
  end
  --check if terminal actions are used and if all player bets are used
  assert(used_bets[1] == 1 and used_bets[2] == 1)
  assert(used_bets:sum(1)[1] == player_actions:size(1))

  --fill the strategy
  node.strategy = arguments.Tensor(actions_count, game_settings.card_count):zero()
  local cf_values = arguments.Tensor(actions_count, game_settings.card_count):zero()

  --we need to compute all values and ranges before dfs call, becasue
  --re-solving will be built from different node in the recursion

  --in first cycle, fill nodes we do not play in and fill strategies and cf-values
  for i=1, actions_count do
    local child_node = node.children[i]
    --check if the bet is possible
    if used_bets[i] == 0 then
      self:_fill_uniformly(child_node, player)
    else
      local action = node.actions[i]
      local values_after_action = resolving:get_action_cfv(action)
      cf_values[i]:copy(values_after_action)
      node.strategy[i] = resolving:get_action_strategy(action)
    end
  end

  --compute ranges for each action
  local range_after_action = node.strategy:clone()
  range_after_action:cmul(range:view(1, game_settings.card_count):expandAs(range_after_action)) -- new range = range * strategy
  --normalize the ranges
  local normalization_factor = range_after_action:sum(2)
  normalization_factor[torch.eq(normalization_factor, 0)] = 1
  range_after_action:cdiv(normalization_factor:expandAs(range_after_action))

  --in second cycle, run dfs computation
  for action = 1, actions_count do
    local child_node = node.children[action]
    if used_bets[action] ~= 0 then

      if not (math.abs(range_after_action[action]:sum(1)[1] - 1) < 0.001) then
        assert(range_after_action[action]:sum() == 0, range_after_action[action]:sum())
        self:_fill_uniformly(child_node, player)
      else
        assert(math.abs(range_after_action[action]:sum(1)[1] - 1) < 0.001)

        local params = {}
        params.node = child_node
        params.range = range_after_action[action]
        params.player = player
        params.cf_values =  cf_values[action]
        params.resolving = resolving
        params.our_last_action = node.actions[action]
        params.opponent_range = opponent_range
        self:_fill_strategies_dfs(params)
      end
    end
  end
end

--- Recursively fills a player's strategy for the subtree rooted at a 
-- chance node.
-- 
-- @param params tree walk parameters (see @{_fill_strategies_dfs})
-- @local
function TreeStrategyFilling:_process_chance_node(params)
  local resolving = params.resolving
  local node = params.node
  local player = params.player
  local range = params.range
  local cf_values = params.cf_values
  local our_last_action = params.our_last_action
  assert(resolving)
  assert(our_last_action)
  assert(not node.terminal and node.current_player == constants.players.chance)
  --on chance node we need to recompute values in next round
  for i = 1,#node.children do
    local child_node = node.children[i]

    assert(child_node.current_player == constants.players.P1)
    assert(not child_node.terminal)
    --computing cf_values for the child node
    local child_cf_values = resolving:get_chance_action_cfv(our_last_action, child_node.board)
    --we need to remove impossible hands from the range and then renormalize it
    local child_range = range:clone()
    local mask = card_tools:get_possible_hand_indexes(child_node.board)
    child_range:cmul(mask)
    local range_weight = child_range:sum(1)[1] --weight should be single number
    child_range:mul(1/range_weight)

    --we should never touch same re-solving again after the chance action, set it to nil
    local params = {}
    params.node = child_node
    params.range = child_range
    params.player = player
    params.cf_values = child_cf_values
    params.resolving = nil
    params.our_last_action = nil
    self:_fill_strategies_dfs(params)
  end
end

--- Recursively fills a player's strategy for a subtree.
-- 
-- @param params a table of tree walk parameters with the following fields:
-- 
-- * `node`: the root of the subtree
--
-- * `player`: the player to fill the strategy for
-- 
-- * `range`: a probability vector over the player's private hands at the node
-- 
-- * `cf_values`: a vector of opponent counterfactual values at the node
-- 
-- * `resolving`: a @{resolving|Resolving} object which was used to
-- re-solve the last player node
-- 
-- * `our_last_action`: the action taken by the player at their last node
-- @local
function TreeStrategyFilling:_fill_strategies_dfs(params)
  assert(params.player == constants.players.chance or params.player == constants.players.P1 or params.player == constants.players.P2)
  if(params.node.terminal) then
    return
  elseif(params.node.current_player == constants.players.chance) then --chance node
    self:_process_chance_node(params)
  elseif(params.node.current_player == params.player ) then
    self:_fill_player_node(params)
  else
    self:_process_opponent_node(params)
  end
end

--- Fills a tree with a player's strategy generated with continual re-solving.
-- 
-- Recursively does continual re-solving on every node of the tree to generate
-- the strategy for that node.
--
-- @param root the root of the tree
-- @param player the player to fill the strategy for
-- @param p1_range a probability vector over the first player's private hands
-- at the root of the tree
-- @param p2_range a probability vector over the second player's private hands
-- at the root of the tree
function TreeStrategyFilling:fill_strategies( root, player, p1_range, p2_range )
  self.current_filling_player = player
  if player == constants.players.chance then
    self:_fill_chance(root)
  else
    assert(player == constants.players.P1 or player == constants.players.P2)
    self:_fill_starting_node(root, player, p1_range, p2_range)
  end
end

--- Fills a tree with uniform random strategies for both players.
-- @param root the root of the tree
function TreeStrategyFilling:fill_uniform_strategy(root)
  self:_fill_uniformly(root, constants.players.P1)
  self:_fill_uniformly(root, constants.players.P2)
end