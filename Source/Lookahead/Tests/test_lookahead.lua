local arguments = require 'Settings.arguments'
local constants = require 'Settings.constants'
local card_tools = require 'Game.card_tools'
local card_to_string = require 'Game.card_to_string_conversion'

require 'Lookahead.lookahead'
require 'Lookahead.resolving'

local resolving = Resolving()
local current_node = {}

current_node.board = card_to_string:string_to_board('Ks')
current_node.street = 2
current_node.current_player = constants.players.P1
current_node.bets = arguments.Tensor{100, 100}

local player_range = card_tools:get_random_range(current_node.board, 2)
local opponent_range = card_tools:get_random_range(current_node.board, 4)

--resolving:resolve_first_node(current_node, player_range, opponent_range)

resolving:resolve(current_node, player_range, opponent_range)

--[[
local lookahead = Lookahead()

local current_node = {}
current_node.board = card_to_string:string_to_board('Ks')
current_node.street = 2
current_node.current_player = constants.players.P1
current_node.bets = arguments.Tensor{100, 100}


lookahead:build_lookahead(current_node)
]]

--[[
local starting_ranges = arguments.Tensor(constants.players_count, constants.card_count)
starting_ranges[1]:copy(card_tools:get_random_range(current_node.board, 2))
starting_ranges[2]:copy(card_tools:get_random_range(current_node.board, 4))

lookahead:resolve_first_node(starting_ranges)

lookahead:get_strategy()
]]

--[[
local player_range = card_tools:get_random_range(current_node.board, 2)
local opponent_cfvs = card_tools:get_random_range(current_node.board, 4)

lookahead:resolve(player_range, opponent_cfvs)


lookahead:get_results()
]]
