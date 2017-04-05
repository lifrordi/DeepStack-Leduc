--- Implements the re-solving interface used by @{resolving} with functions
-- that do nothing.
-- 
-- Used for debugging.
-- @classmod mock_resolving

require 'Lookahead.lookahead'
require 'Lookahead.cfrd_gadget'
require 'Tree.tree_builder'
require 'Tree.tree_visualiser'
local arguments = require 'Settings.arguments'
local constants = require 'Settings.constants'
local tools = require 'tools'
local card_tools = require 'Game.card_tools'
local game_settings = require 'Settings.game_settings'

local MockResolving = torch.class('MockResolving')

--- Constructor
function MockResolving:__init()
end

--- Does nothing.
-- @param node the node to "re-solve"
-- @param[opt] player_range not used
-- @param[opt] opponent_range not used
-- @see resolving.resolve_first_node
function MockResolving:resolve_first_node(node, player_range, opponent_range)
  self.node = node
  self.action_count = self.node.actions:size(1)
end

--- Does nothing.
-- @param node the node to "re-solve"
-- @param[opt] player_range not used
-- @param[opt] opponent_cfvs not used
-- @see resolving.resolve
function MockResolving:resolve(node, player_range, opponent_cfvs)
  self.node = node
  self.action_count = self.node.actions:size(1)
end

--- Gives the possible actions at the re-solve node.
-- @return the actions that can be taken at the re-solve node
-- @see resolving.get_possible_actions
function MockResolving:get_possible_actions()
  return self.node.actions
end

--- Returns an arbitrary vector.
-- @return a vector of 1s
-- @see resolving.get_root_cfv
function MockResolving:get_root_cfv()
  return arguments.Tensor(game_settings.card_count):fill(1)
end

--- Returns an arbitrary vector.
-- @param[opt] action not used
-- @return a vector of 1s
-- @see resolving.get_action_cfv
function MockResolving:get_action_cfv(action)
  return arguments.Tensor(game_settings.card_count):fill(1)
end

--- Returns an arbitrary vector.
-- @param[opt] player_action not used
-- @param[opt] board not used
-- @return a vector of 1s
-- @see resolving.get_chance_action_cfv
function MockResolving:get_chance_action_cfv(player_action, board)
  return arguments.Tensor(game_settings.card_count):fill(1)
end

--- Returns an arbitrary vector.
-- @param[opt] action not used
-- @return a vector of 1s
-- @see resolving.get_action_strategy
function MockResolving:get_action_strategy(action)
  return arguments.Tensor(game_settings.card_count):fill(1)
end