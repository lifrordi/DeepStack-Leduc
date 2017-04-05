local arguments = require 'Settings.arguments'
local constants = require 'Settings.constants'
local card_tools = require 'Game.card_tools'
local card_to_string = require 'Game.card_to_string_conversion'
local game_settings = require 'Settings.game_settings'
require 'Tree.tree_builder'
require 'Tree.tree_visualiser'
require 'Tree.tree_values'
require 'Tree.tree_cfr'
require 'Tree.tree_strategy_filling'
require 'Tree.tree_visualiser'
require 'Tree.tree_values'

local builder = PokerTreeBuilder()

local params = {}
params.root_node = {}
params.root_node.board = card_to_string:string_to_board('')
params.root_node.street = 1
params.root_node.current_player = constants.players.P1
params.root_node.bets = arguments.Tensor{100, 100}

local tree = builder:build_tree(params)

local filling = TreeStrategyFilling()

local range1 = card_tools:get_uniform_range(params.root_node.board)
local range2 = card_tools:get_uniform_range(params.root_node.board)

filling:fill_strategies(tree, 1, range1, range2)
filling:fill_strategies(tree, 2, range1, range2)


local starting_ranges = arguments.Tensor(constants.players_count, game_settings.card_count)
starting_ranges[1]:copy(range1)
starting_ranges[2]:copy(range2)

local tree_values = TreeValues()
tree_values:compute_values(tree, starting_ranges)

print('Exploitability: ' .. tree.exploitability .. '[chips]' )

local visualiser = TreeVisualiser()
visualiser:graphviz(tree)
