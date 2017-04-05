--- Generates neural net training data by solving random poker situations.
-- @module data_generation
local arguments = require 'Settings.arguments'
local game_settings = require 'Settings.game_settings'
local card_generator = require 'DataGeneration.random_card_generator'
local constants = require 'Settings.constants'
require 'DataGeneration.range_generator'
require 'Nn.bucketer'
require 'Nn.bucket_conversion'
require 'TerminalEquity.terminal_equity'
require 'Lookahead.lookahead'
require 'Lookahead.resolving'


local M = {}

--- Generates training and validation files by sampling random poker
-- situations and solving them.
-- 
-- Makes two calls to @{generate_data_file}. The files are saved to 
-- @{arguments.data_path}, respectively appended with `valid` and `train`.
--
-- @param train_data_count the number of training examples to generate
-- @param valid_data_count the number of validation examples to generate
function M:generate_data(train_data_count, valid_data_count)
  --valid data generation 
  local file_name = arguments.data_path .. 'valid'
  local timer = torch.Timer()
  timer:reset()
  print('Generating validation data ...')
  self:generate_data_file(valid_data_count, file_name)
  print('valid gen time: ' .. timer:time().real)
  timer:reset()
  --train data generation 
  print('Generating training data ...')
  file_name = arguments.data_path .. 'train'
  self:generate_data_file(train_data_count, file_name) 
  print('Generation time: ' .. timer:time().real)
  print('Done')
end

--- Generates data files containing examples of random poker situations with
-- counterfactual values from an associated solution.
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
  local target_size = bucket_count * constants.players_count
  local targets = arguments.Tensor(data_count, target_size)
  local input_size = bucket_count * constants.players_count + 1
  local inputs = arguments.Tensor(data_count, input_size)
  local mask = arguments.Tensor(data_count, bucket_count):zero()
  local bucket_conversion = BucketConversion()
  for batch = 1, batch_count do 
    local board = card_generator:generate_cards(game_settings.board_card_count)
    range_generator:set_board(board)
    bucket_conversion:set_board(board)
	
    --generating ranges
    local ranges = arguments.Tensor(constants.players_count, batch_size, game_settings.card_count)
    for player = 1, constants.players_count do 
      range_generator:generate_range(ranges[player])
    end
	
    --generating pot sizes between ante and stack - 0.1
    local min_pot = arguments.ante
    local max_pot = arguments.stack - 0.1
    local pot_range = max_pot - min_pot
     
    local random_pot_sizes = torch.rand(arguments.gen_batch_size, 1):mul(pot_range):add(min_pot)
    
    --pot features are pot sizes normalized between (ante/stack,1)
    local pot_size_features = random_pot_sizes:clone():mul(1/arguments.stack)
    
    --translating ranges to features 
    local batch_index = {(batch -1) * batch_size + 1, batch * batch_size }
    local pot_feature_index =  -1
    inputs[{batch_index, pot_feature_index}]:copy(pot_size_features)
    local player_indexes = {{1, bucket_count}, {bucket_count +1, bucket_count * 2}}
    for player = 1, constants.players_count do 
      local player_index = player_indexes[player]
      bucket_conversion:card_range_to_bucket_range(ranges[player], inputs[{batch_index, player_index}])
    end
	
    --computaton of values using re-solving
    local values = arguments.Tensor(constants.players_count, batch_size, game_settings.card_count)
    for i=1,batch_size do 
      local resolving = Resolving()
      local current_node = {}

      current_node.board = board
      current_node.street = 2
      current_node.current_player = constants.players.P1
      local pot_size = pot_size_features[i][1] * arguments.stack
      current_node.bets = arguments.Tensor{pot_size, pot_size}
      local p1_range = ranges[1][i]
      local p2_range = ranges[2][i]
      resolving:resolve_first_node(current_node, p1_range, p2_range)
      local root_values = resolving:get_root_cfv_both_players()
      root_values:mul(1/pot_size)
      values[{{}, i, {}}]:copy(root_values)
    end

    
    --translating values to nn targets
    for player = 1, constants.players_count do 
      local player_index = player_indexes[player]
      bucket_conversion:card_range_to_bucket_range(values[player], targets[{batch_index, player_index}])
    end 
    --computing a mask of possible buckets
    local bucket_mask = bucket_conversion:get_possible_bucket_mask()
    mask[{batch_index, {}}]:copy(bucket_mask:expand(batch_size, bucket_count))
  end  
  torch.save(file_name .. '.inputs', inputs:float())
  torch.save(file_name .. '.targets', targets:float())
  torch.save(file_name .. '.mask', mask:float())
end

return M