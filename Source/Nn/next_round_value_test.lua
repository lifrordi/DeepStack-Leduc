require 'Nn.next_round_value'
--require 'Nn.mock_nn'
require 'Nn.mock_nn_terminal'
require 'TerminalEquity.terminal_equity'


require 'Nn.value_nn'



local arguments = require 'Settings.arguments'
local game_settings = require 'Settings.game_settings'
local card_to_string = require 'Game.card_to_string_conversion'
local card_tools = require 'Game.card_tools'


--local next_round_value =  NextRoundValue()
--print(next_round_value._range_matrix)
--[[ test of card to bucket range translation
local range = torch.range(1, 6):float():view(1, -1)
local next_round_range = arguments.Tensor(1, next_round_value.bucket_count * next_round_value.board_count)
next_round_value:_card_range_to_bucket_range(range, next_round_range)
print(next_round_range)
]]

--test of get_value functionality
local mock_nn = MockNnTerminal()
--local mock_nn = ValueNn()
local next_round_value = NextRoundValue(mock_nn)

--local bets = torch.range(1,1):float():mul(100)
local bets = torch.Tensor(1):fill(1200)

next_round_value:start_computation(bets)

local ranges = arguments.Tensor(1, 2, game_settings.card_count):fill(1/4)
local values = arguments.Tensor(1, 2, game_settings.card_count)


local x = arguments.Tensor()
torch.manualSeed(0)
ranges[1][1]:copy(torch.Tensor({1,1,0,0,0,0}))
ranges[1][2]:copy(torch.Tensor({1,1,1,1,1,1}))

next_round_value:get_value(ranges, values)

print(values)

----[[
local ranges_2 = ranges:view(2, game_settings.card_count):clone()
local values_2 = ranges_2:clone():fill(-1)

local terminal_equity = TerminalEquity()
terminal_equity:set_board(torch.Tensor{})
terminal_equity:call_value(ranges_2, values_2)
print('terminal_equity')
print(values_2)
---]]

--[[
local board = card_to_string:string_to_board('Ks')

local values_3 = values:clone():fill(-1)
next_round_value:get_value_on_board(board, values_3)

print(values_3)
]]



