--- Implements depth-limited re-solving at a node of the game tree.
-- Internally uses @{cfrd_gadget|CFRDGadget} TODO SOLVER
-- @classmod resolving
require 'Lookahead.lookahead'
require 'Lookahead.cfrd_gadget'
require 'Tree.tree_builder'
require 'Tree.tree_visualiser'
local arguments = require 'Settings.arguments'
local constants = require 'Settings.constants'
local tools = require 'tools'
local card_tools = require 'Game.card_tools'

local Resolving = torch.class('Resolving')

--- Constructor
function Resolving:__init()
  self.tree_builder = PokerTreeBuilder()
end

--- Builds a depth-limited public tree rooted at a given game node.
-- @param node the root of the tree
-- @local
function Resolving:_create_lookahead_tree(node)
  local build_tree_params = {}
  build_tree_params.root_node = node
  build_tree_params.limit_to_street = true

  self.lookahead_tree = self.tree_builder:build_tree(build_tree_params)
end

--- Re-solves a depth-limited lookahead using input ranges.
--
-- Uses the input range for the opponent instead of a gadget range, so only
-- appropriate for re-solving the root node of the game tree (where ranges 
-- are fixed).
--
-- @param node the public node at which to re-solve
-- @param player_range a range vector for the re-solving player
-- @param opponent_range a range vector for the opponent
function Resolving:resolve_first_node(node, player_range, opponent_range)
  self:_create_lookahead_tree(node)
  
  self.lookahead = Lookahead()
  self.lookahead:build_lookahead(self.lookahead_tree)  
  
  self.lookahead:resolve_first_node(player_range, opponent_range)
  
  self.resolve_results = self.lookahead:get_results()
  return self.resolve_results 
end

--- Re-solves a depth-limited lookahead using an input range for the player and
-- the @{cfrd_gadget|CFRDGadget} to generate ranges for the opponent.
-- 
-- @param node the public node at which to re-solve
-- @param player_range a range vector for the re-solving player
-- @param opponent_cfvs a vector of cfvs achieved by the opponent
-- before re-solving
function Resolving:resolve(node, player_range, opponent_cfvs)
  assert(card_tools:is_valid_range(player_range, node.board))
  
  self:_create_lookahead_tree(node)
  
  self.lookahead = Lookahead()  
  self.lookahead:build_lookahead(self.lookahead_tree)
  
  self.lookahead:resolve(player_range, opponent_cfvs)
  
  self.resolve_results = self.lookahead:get_results()
  return self.resolve_results
end

--- Gives the index of the given action at the node being re-solved.
-- 
-- The node must first be re-solved with @{resolve} or @{resolve_first_node}.
-- @param action a legal action at the node
-- @return the index of the action
-- @local
function Resolving:_action_to_action_id(action)
  local actions = self:get_possible_actions(action)
  local action_id = -1
  for i=1,actions:size(1) do
    if action == actions[i] then
      action_id = i
    end
  end
  
  assert(action_id ~= -1)
  
  return action_id
end

--- Gives a list of possible actions at the node being re-solved.
-- 
-- The node must first be re-solved with @{resolve} or @{resolve_first_node}.
-- @return a list of legal actions
function Resolving:get_possible_actions()
  return self.lookahead_tree.actions
end

--- Gives the average counterfactual values that the re-solve player received
-- at the node during re-solving.
--
-- The node must first be re-solved with @{resolve_first_node}.
--
-- @return a vector of cfvs
function Resolving:get_root_cfv()
  return self.resolve_results.root_cfvs
end

--- Gives the average counterfactual values that each player received
-- at the node during re-solving.
--
-- Usefull for data generation for neural net training
--
-- The node must first be re-solved with @{resolve_first_node}.
--
-- @return a 2xK tensor of cfvs, where K is the range size
function Resolving:get_root_cfv_both_players()
  return self.resolve_results.root_cfvs_both_players
end

--- Gives the average counterfactual values that the opponent received
-- during re-solving after the re-solve player took a given action.
-- 
-- Used during continual re-solving to track opponent cfvs. The node must 
-- first be re-solved with @{resolve} or @{resolve_first_node}.
-- 
-- @param action the action taken by the re-solve player at the node being 
-- re-solved
-- @return a vector of cfvs
function Resolving:get_action_cfv(action)
  local action_id = self:_action_to_action_id(action)
  return self.resolve_results.children_cfvs[action_id]
end

--- Gives the average counterfactual values that the opponent received
-- during re-solving after a chance event (the betting round changes and
-- more cards are dealt).
-- 
-- Used during continual re-solving to track opponent cfvs. The node must 
-- first be re-solved with @{resolve} or @{resolve_first_node}.
--
-- @param action the action taken by the re-solve player at the node being 
-- re-solved
-- @param board a vector of board cards which were updated by the chance event
-- @return a vector of cfvs
function Resolving:get_chance_action_cfv(action, board)
  local action_id = self:_action_to_action_id(action)
  return self.lookahead:get_chance_action_cfv(action_id, board)
end

--- Gives the probability that the re-solved strategy takes a given action.
-- 
-- The node must first be re-solved with @{resolve} or @{resolve_first_node}.
--
-- @param action a legal action at the re-solve node
-- @return a vector giving the probability of taking the action with each 
-- private hand
function Resolving:get_action_strategy(action)
  local action_id = self:_action_to_action_id(action)
  return self.resolve_results.strategy[action_id]
end