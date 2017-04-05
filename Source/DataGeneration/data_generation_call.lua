--- Generates neural net training data by evaluating terminal equity for poker
-- situations.
-- 
-- Evaluates terminal equity (assuming both players check/call to the end of
-- the game) instead of re-solving. Used for debugging.
-- @module data_generation_call
local arguments = require 'Settings.arguments'
local game_settings = require 'Settings.game_settings'
local card_generator = require 'DataGeneration.random_card_generator'
require 'DataGeneration.range_generator'
require 'Nn.bucketer'
require 'Nn.bucket_conversion'
require 'TerminalEquity.terminal_equity'

local M = {}

--- Generates training and validation files by evaluating terminal
-- equity for random poker situations.
-- 
-- Makes two calls to @{generate_data_file}. The files are saved to 
-- @{arguments.data_path}, respectively appended with `valid` and `train`.
--
-- @param train_data_count the number of training examples to generate
-- @param valid_data_count the number of validation examples to generate
function M:generate_data(train_data_count, valid_data_count)
  --valid data generation 
  local file_name = arguments.data_path .. 'valid'
  self:generate_data_file(valid_data_count, file_name) 
  --train data generation 
  file_name = arguments.data_path .. 'train'
  self:generate_data_file(train_data_count, file_name) 
end

--- Generates data files containing examples of random poker situations with
-- associated terminal equity.
-- 
-- Each poker situation is randomly generated using @{range_generator} and 
-- @{random_card_generator}. For description of neural net input and target
-- type, see @{net_builder}.
-- 
-- @param data_count the number of examples to generate
-- @param file_name the prefix of the files where the data is saved (appended
-- with `.inputs`, `.targets`, and `.mask`).
function M:generate_data_file(data_count, file_name)
  local range_generator = RangeGenerator()
  local batch_size = arguments.gen_batch_size
  assert(data_count % batch_size == 0, 'data count has to be divisible by the batch size')
  local batch_count = data_count / batch_size
  local bucketer = Bucketer()
  local bucket_count = bucketer:get_bucket_count()
  local player_count = 2
  local target_size = bucket_count * player_count
  local targets = arguments.Tensor(data_count, target_size)
  local input_size = bucket_count * player_count + 1
  local inputs = arguments.Tensor(data_count, input_size)
  local mask = arguments.Tensor(data_count, bucket_count):zero()
  local bucket_conversion = BucketConversion()
  local equity = TerminalEquity()
  for batch = 1, batch_count do 
    local board = card_generator:generate_cards(game_settings.board_card_count)
    range_generator:set_board(board)
    bucket_conversion:set_board(board)
    equity:set_board(board)
	
    --generating ranges
    local ranges = arguments.Tensor(player_count, batch_size, game_settings.card_count)
    for player = 1, player_count do 
      range_generator:generate_range(ranges[player])
    end
    local pot_sizes = arguments.Tensor(arguments.gen_batch_size, 1)
	
    --generating pot features
    pot_sizes:copy(torch.rand(batch_size))
    
    --translating ranges to features 
    local batch_index = {(batch -1) * batch_size + 1, batch * batch_size }
    local pot_feature_index =  -1
    inputs[{batch_index, pot_feature_index}]:copy(pot_sizes)
    local player_indexes = {{1, bucket_count}, {bucket_count +1, bucket_count * 2}}
    for player = 1, player_count do 
      local player_idnex = player_indexes[player]
      bucket_conversion:card_range_to_bucket_range(ranges[player], inputs[{batch_index, player_idnex}])
    end
	
    --computaton of values using terminal equity
    local values = arguments.Tensor(player_count, batch_size, game_settings.card_count)
    for player = 1, player_count do
      local opponent = 3 - player
      equity:call_value(ranges[opponent], values[player])
    end
	
    --translating values to nn targets
    for player = 1, player_count do 
      local player_idnex = player_indexes[player]
      bucket_conversion:card_range_to_bucket_range(values[player], targets[{batch_index, player_idnex}])
    end 
	
    --computing a mask of possible buckets
    local bucket_mask = bucket_conversion:get_possible_bucket_mask()
    mask[{batch_index, {}}]:copy(bucket_mask:expand(batch_size, bucket_count))
  end  
  torch.save(file_name .. '.inputs', inputs)
  torch.save(file_name .. '.targets', targets)
  torch.save(file_name .. '.mask', mask)
end

return M