--- Performs the main steps of continual re-solving, tracking player range
-- and opponent counterfactual values so that re-solving can be done at each
-- new game state.
-- @classmod continual_resolving

require 'Lookahead.resolving'
local arguments = require 'Settings.arguments'
local constants = require "Settings.constants"
local card_tools = require 'Game.card_tools'

local ContinualResolving = torch.class('ContinualResolving')

--- Constructor. Does a depth-limited solve of the game's first node.
function ContinualResolving:__init()
  self.starting_player_range = card_tools:get_uniform_range(arguments.Tensor{})
  self:resolve_first_node()
end

--- Solves a depth-limited lookahead from the first node of the game to get 
-- opponent counterfactual values.
-- 
-- The cfvs are stored in the field `starting_cfvs_p1`. Because this is the
-- first node of the game, exact ranges are known for both players, so
-- opponent cfvs are not necessary for solving.
function ContinualResolving:resolve_first_node()
  self.first_node_resolving = Resolving()
  local first_node = {}
  first_node.board = arguments.Tensor{}
  first_node.street = 1
  first_node.current_player = constants.players.P1
  first_node.bets = arguments.Tensor{arguments.ante, arguments.ante}

  --create the starting ranges
  local player_range = card_tools:get_uniform_range(first_node.board)
  local opponent_range = card_tools:get_uniform_range(first_node.board)

  --create re-solving and re-solve the first node
  self.first_node_resolving = Resolving()
  self.first_node_resolving:resolve_first_node(first_node, player_range, opponent_range)
  --store the initial CFVs
  self.starting_cfvs_p1 = self.first_node_resolving:get_root_cfv()
end

--- Re-initializes the continual re-solving to start a new game from the root
-- of the game tree.
-- @param state the first state where the re-solving player acts in the new
-- game (a table of the type returned by @{protocol_to_node.parse_state})
function ContinualResolving:start_new_hand(state)
  self.last_node = nil
  self.decision_id = 0
  self.position = state.position
  self.hand_id = state.hand_id
end

--- Re-solves a node to choose the re-solving player's next action.
-- @param node the game node where the re-solving player is to act (a table of 
-- the type returned by @{protocol_to_node.parsed_state_to_node})
-- @param state the game state where the re-solving player is to act
-- (a table of the type returned by @{protocol_to_node.parse_state})
-- @local
function ContinualResolving:_resolve_node(node, state)
  assert(self.decision_id)
  --1.0 first node and P1 position
  --no need to update an invariant since this is the very first situation
  if self.decision_id == 0 and self.position == constants.players.P1 then
    --the strategy computation for the first decision node has been already set up
    self.current_player_range = self.starting_player_range:clone()    
    self.resolving = self.first_node_resolving
  --2.0 other nodes - we need to update the invariant
  else
    assert(not node.terminal)
    assert(node.current_player == self.position)

    --2.1 update the invariant based on actions we did not make
    self:_update_invariant(node, state)
    
    --2.2 re-solve
    self.resolving = Resolving()    
    self.resolving:resolve(node, self.current_player_range, self.current_opponent_cfvs_bound)
  end
end

--- Updates the player's range and the opponent's counterfactual values to be
-- consistent with game actions since the last re-solved state.
-- Updates it only for actions we did not make, since we update the invariant for our action as soon as we make it.
--
-- @param node the game node where the re-solving player is to act (a table of 
-- the type returned by @{protocol_to_node.parsed_state_to_node})
-- @param state the game state where the re-solving player is to act
-- (a table of the type returned by @{protocol_to_node.parse_state})
-- @local
function ContinualResolving:_update_invariant(node, state)
  --1.0 street has changed
  if self.last_node and self.last_node.street ~= node.street then
    assert(self.last_node.street + 1 == node.street)

    --1.1 opponent cfvs
    --if the street has changed, the resonstruction API simply gives us CFVs        
    self.current_opponent_cfvs_bound = self.resolving:get_chance_action_cfv(self.last_bet, node.board)
   
    --1.2 player range
    --if street has change, we have to mask out the colliding hands
    self.current_player_range = card_tools:normalize_range(node.board, self.current_player_range)
  --2.0 first decision for P2
  elseif self.decision_id == 0 then
    assert(self.position == constants.players.P2)
    assert(node.street == 1)

    self.current_player_range = self.starting_player_range:clone()
    self.current_opponent_cfvs_bound = self.starting_cfvs_p1:clone()
  --3.0 handle game within the street
  else    
    assert(self.last_node.street == node.street)
  end    
end

--- Re-solves a node and chooses the re-solving player's next action.
-- @param node the game node where the re-solving player is to act (a table of 
-- the type returned by @{protocol_to_node.parsed_state_to_node})
-- @param state the game state where the re-solving player is to act
-- (a table of the type returned by @{protocol_to_node.parse_state})
-- @return an action sampled from the re-solved strategy at the given state,
-- with the fields:
-- 
-- * `action`: an element of @{constants.acpc_actions}
-- 
-- * `raise_amount`: the number of chips to raise (if `action` is raise)
function ContinualResolving:compute_action(node, state)
  self:_resolve_node(node, state)  
  local sampled_bet = self:_sample_bet(node, state)  
  
  self.decision_id = self.decision_id + 1
  self.last_bet = sampled_bet
  self.last_node = node
  
  local out = self:_bet_to_action(node, sampled_bet)
  return out
end

--- Samples an action to take from the strategy at the given game state.
-- @param node the game node where the re-solving player is to act (a table of 
-- the type returned by @{protocol_to_node.parsed_state_to_node})
-- @param state the game state where the re-solving player is to act
-- (a table of the type returned by @{protocol_to_node.parse_state})
-- @return an index representing the action chosen
-- @local
function ContinualResolving:_sample_bet(node, state)
  --1.0 get the possible bets in the node
  local possible_bets = self.resolving:get_possible_actions()
  local actions_count = possible_bets:size(1)
  
  --2.0 get the strategy for the current hand since the strategy is computed for all hands
  local hand_strategy = arguments.Tensor(actions_count)
  
  for i = 1, actions_count do
    local action_bet = possible_bets[i]
    local action_strategy = self.resolving:get_action_strategy(action_bet)
    hand_strategy[i] = action_strategy[self.hand_id]
  end
  
  assert(math.abs(1 - hand_strategy:sum()) < 0.001)
  
  print("strategy:")
  print(hand_strategy)
  
  --3.0 sample the action by doing cumsum and uniform sample
  local hand_strategy_cumsum = torch.cumsum(hand_strategy)
  local r = torch.uniform()

  local sampled_bet = possible_bets[hand_strategy_cumsum:gt(r)][1]  
  print("playing action that has prob: " .. hand_strategy[hand_strategy_cumsum:gt(r)][1])
  
  --4.0 update the invariants based on our action
  self.current_opponent_cfvs_bound = self.resolving:get_action_cfv(sampled_bet)

  local strategy = self.resolving:get_action_strategy(sampled_bet)
  self.current_player_range:cmul(strategy)
  self.current_player_range = card_tools:normalize_range(node.board, self.current_player_range)
  
  return sampled_bet
end

--- Converts an internal action representation into a cleaner format.
-- @param node the game node where the re-solving player is to act (a table of 
-- the type returned by @{protocol_to_node.parsed_state_to_node})
-- @param sampled_bet the index of the action to convert
-- @return a table specifying the action, with the fields:
-- 
-- * `action`: an element of @{constants.acpc_actions}
-- 
-- * `raise_amount`: the number of chips to raise (if `action` is raise)
-- @local
function ContinualResolving:_bet_to_action(node, sampled_bet)
  if sampled_bet == constants.actions.fold then
    return {action = constants.acpc_actions.fold}
  elseif sampled_bet == constants.actions.ccall then
    return {action = constants.acpc_actions.ccall}
  else
    assert(sampled_bet >= 0)
    return {action = constants.acpc_actions.raise, raise_amount = sampled_bet}
  end
end