--- Implements the same interface as @{value_nn}, but without uses terminal
-- equity evaluation instead of a neural net.
-- 
-- Can be used to replace the neural net during debugging.
-- @classmod mock_nn_terminal

require 'torch'
require 'Nn.bucketer'
require 'TerminalEquity.terminal_equity'
local game_settings = require  'Settings.game_settings'
local card_tools = require 'Game.card_tools'
local arguments = require 'Settings.arguments'

local MockNnTerminal = torch.class('MockNnTerminal')

--- Constructor. Creates an equity matrix with entries for every possible
-- pair of buckets.
function MockNnTerminal:__init()
  self.bucketer = Bucketer()
  self.bucket_count = self.bucketer:get_bucket_count()
  self.equity_matrix = arguments.Tensor(self.bucket_count, self.bucket_count):zero()
  --filling equity matrix
  local boards = card_tools:get_second_round_boards()
  self.board_count = boards:size(1)
  self.terminal_equity = TerminalEquity()
  for i = 1, self.board_count do 
    local board = boards[i]
    self.terminal_equity:set_board(board)
    local call_matrix = self.terminal_equity:get_call_matrix()
    local buckets = self.bucketer:compute_buckets(board)
    for c1 = 1, game_settings.card_count do 
      for c2 = 1, game_settings.card_count do 
        local b1 = buckets[c1]
        local b2 = buckets[c2]
        if( b1 > 0 and b2 > 0 ) then
          local matrix_entry = call_matrix[c1][c2]
          self.equity_matrix[b1][b2] = matrix_entry
        end
      end
    end
  end
end

--- Gives the expected showdown equity of the two players' ranges.
-- @param inputs An NxI tensor containing N instances of neural net inputs. 
-- See @{net_builder} for details of each input.
-- @param outputs An NxO tensor in which to store N sets of expected showdown
-- counterfactual values for each player.
function MockNnTerminal:get_value(inputs, outputs)

  assert(outputs:dim() == 2 )
  local bucket_count = outputs:size(2) / 2
  local batch_size = outputs:size(1)
  local player_indexes = {{1, self.bucket_count}, {self.bucket_count + 1, 2 * self.bucket_count}}
  local players_count = 2
  for player =1, players_count do 
    local player_idx = player_indexes[player]
    local opponent_idx = player_indexes[3- player]
    outputs[{{}, player_idx}]:mm(inputs[{{}, opponent_idx}], self.equity_matrix)
  end
end