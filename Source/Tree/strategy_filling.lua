--- Fills a game's public tree with a uniform strategy. In particular, fills
-- the chance nodes with the probability of each outcome.
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
-- action that leads to the `i`th child when the player holds the `j`th card.
-- 
-- For a chance node, `strategy[i][j]` gives the probability of reaching the 
-- `i`th child for either player when that player holds the `j`th card.
-- @classmod strategy_filling

local arguments = require 'Settings.arguments'
local constants = require 'Settings.constants'
local game_settings = require 'Settings.game_settings'
local math = require 'math'
local card_tools = require 'Game.card_tools'

local StrategyFilling = torch.class('StrategyFilling')

--- Constructor
function StrategyFilling:__init()
end

--- Fills a chance node with the probability of each outcome.
-- @param node the chance node
-- @local
function StrategyFilling:_fill_chance(node)
  assert(not node.terminal)

  --filling strategy
  --we will fill strategy with an uniform probability, but it has to be zero for hands that are not possible on
  --corresponding board
  node.strategy = arguments.Tensor(#node.children, game_settings.card_count):fill(0)
  --setting probability of impossible hands to 0
  for i = 1,#node.children do
    local child_node = node.children[i]
    local mask = card_tools:get_possible_hand_indexes(child_node.board):byte()
    node.strategy[i]:fill(0)
    --remove 2 because each player holds one card
    node.strategy[i][mask] = 1.0 / (game_settings.card_count - 2)
  end
end

--- Fills a player node with a uniform strategy.
-- @param node the player node
-- @local
function StrategyFilling:_fill_uniformly(node)
  assert(node.current_player == constants.players.P1 or node.current_player == constants.players.P2)

  if(node.terminal) then
    return
  end

  node.strategy = arguments.Tensor(#node.children, game_settings.card_count):fill(1.0 / #node.children)
end

--- Fills a node with a uniform strategy and recurses on the children.
-- @param node the node
-- @local
function StrategyFilling:_fill_uniform_dfs(node)
  if node.current_player == constants.players.chance then
    self:_fill_chance(node)
  else
    self:_fill_uniformly(node)
  end

  for i=1,#node.children do
    self:_fill_uniform_dfs(node.children[i])
  end
end

--- Fills a public tree with a uniform strategy.
-- @param tree a public tree for Leduc Hold'em or variant
function StrategyFilling:fill_uniform(tree)
  self:_fill_uniform_dfs(tree)
end