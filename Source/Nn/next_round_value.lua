--- Uses the neural net to estimate value at the end of the first betting round.
-- @classmod next_round_value

require 'torch'
require 'math'
require 'Nn.bucketer'
local card_tools = require 'Game.card_tools'
local arguments = require 'Settings.arguments'
local game_settings = require 'Settings.game_settings'
local constants = require 'Settings.constants'

local NextRoundValue = torch.class('NextRoundValue')

--- Constructor.
-- 
-- Creates a tensor that can translate hand ranges to bucket ranges
-- on any board.
-- @param nn the neural network
function NextRoundValue:__init(nn)
  self.nn = nn
  self:_init_bucketing()
end

--- Initializes the tensor that translates hand ranges to bucket ranges.
-- @local
function NextRoundValue:_init_bucketing()
  self.bucketer = Bucketer()
  self.bucket_count = self.bucketer:get_bucket_count()
  local boards = card_tools:get_second_round_boards()
  self.board_count = boards:size(1)
  self._range_matrix = arguments.Tensor(game_settings.card_count, self.board_count * self.bucket_count ):zero()
  self._range_matrix_board_view = self._range_matrix:view(game_settings.card_count, self.board_count, self.bucket_count)

  for idx = 1, self.board_count do
    local board = boards[idx]
    
    local buckets = self.bucketer:compute_buckets(board)
    local class_ids = torch.range(1, self.bucket_count)

    if arguments.gpu then 
      buckets = buckets:cuda() 
      class_ids = class_ids:cuda()
    else
      class_ids = class_ids:float() 
    end

    class_ids = class_ids:view(1, self.bucket_count):expand(game_settings.card_count, self.bucket_count)
    local card_buckets = buckets:view(game_settings.card_count, 1):expand(game_settings.card_count, self.bucket_count)

    --finding all strength classes      
    --matrix for transformation from card ranges to strength class ranges 
    self._range_matrix_board_view[{{}, idx, {}}][torch.eq(class_ids, card_buckets)] = 1
  end

  --matrix for transformation from class values to card values
  self._reverse_value_matrix = self._range_matrix:t():clone()
  --we need to div the matrix by the sum of possible boards (from point of view of each hand)
  local weight_constant = 1/(self.board_count - 2) -- count
  self._reverse_value_matrix:mul(weight_constant)
end

--- Converts a range vector over private hands to a range vector over buckets.
-- @param card_range a probability vector over private hands
-- @param bucket_range a vector in which to store the output probabilities
--  over buckets
-- @local
function NextRoundValue:_card_range_to_bucket_range(card_range, bucket_range)
  bucket_range:mm(card_range, self._range_matrix)
end

--- Converts a value vector over buckets to a value vector over private hands.
-- @param bucket_value a value vector over buckets
-- @param card_value a vector in which to store the output values over 
-- private hands
-- @local
function NextRoundValue:_bucket_value_to_card_value(bucket_value, card_value)
  card_value:mm(bucket_value, self._reverse_value_matrix)
end

--- Converts a value vector over buckets to a value vector over private hands
-- given a particular set of board cards.
-- @param board a non-empty vector of board cards
-- @param bucket_value a value vector over buckets
-- @param card_value a vector in which to store the output values over 
-- private hands
-- @local
function NextRoundValue:_bucket_value_to_card_value_on_board(board, bucket_value, card_value)
  local board_idx = card_tools:get_board_index(board)
  local board_matrix = self._range_matrix_board_view[{{}, board_idx, {}}]:t()
  local serialized_card_value = card_value:view(-1, game_settings.card_count)
  local serialized_bucket_value = bucket_value[{{}, {}, board_idx, {}}]:clone():view(-1, self.bucket_count)
  serialized_card_value:mm(serialized_bucket_value, board_matrix)
end

--- Initializes the value calculator with the pot size of each state that
-- we are going to evaluate.
-- 
-- During continual re-solving, there is one pot size for each initial state
-- of the second betting round (before board cards are dealt).
-- @param pot_sizes a vector of pot sizes
-- betting round ends
function NextRoundValue:start_computation(pot_sizes)
  self.iter = 0
  self.pot_sizes = pot_sizes:view(-1, 1):clone()
  self.batch_size = pot_sizes:size(1)
end

--- Gives the predicted counterfactual values at each evaluated state, given
-- input ranges.
-- 
-- @{start_computation} must be called first. Each state to be evaluated must
-- be given in the same order that pot sizes were given for that function.
-- Keeps track of iterations internally, so should be called exactly once for
-- every iteration of continual re-solving.
--
-- @param ranges An Nx2xK tensor, where N is the number of states evaluated
-- (must match input to @{start_computation}), 2 is the number of players, and
-- K is the number of private hands. Contains N sets of 2 range vectors.
-- @param values an Nx2xK tensor in which to store the N sets of 2 value vectors
-- which are output
function NextRoundValue:get_value(ranges, values)
  assert(ranges and values)
  assert(ranges:size(1) == self.batch_size)
  self.iter = self.iter + 1
  if self.iter == 1 then
    --initializing data structures
    self.next_round_inputs = arguments.Tensor(self.batch_size,  self.board_count, (self.bucket_count * constants.players_count + 1)):zero()
    self.next_round_values = arguments.Tensor(self.batch_size, self.board_count, constants.players_count,  self.bucket_count ):zero()
    self.transposed_next_round_values = arguments.Tensor(self.batch_size, constants.players_count, self.board_count, self.bucket_count)
    self.next_round_extended_range = arguments.Tensor(self.batch_size, constants.players_count, self.board_count * self.bucket_count ):zero()
    self.next_round_serialized_range = self.next_round_extended_range:view(-1, self.bucket_count)
    self.range_normalization = arguments.Tensor()
    self.value_normalization = arguments.Tensor(self.batch_size, constants.players_count, self.board_count)
    --handling pot feature for the nn
    local nn_bet_input = self.pot_sizes:clone():mul(1/ arguments.stack)
    nn_bet_input = nn_bet_input:view(-1, 1):expand(self.batch_size, self.board_count)
    self.next_round_inputs[{{}, {}, {-1}}]:copy(nn_bet_input)
  end
  
  --we need to find if we need remember something in this iteration
  local use_memory = self.iter > arguments.cfr_skip_iters
  if use_memory and self.iter == arguments.cfr_skip_iters + 1 then
    --first iter that we need to remember something - we need to init data structures
    self.range_normalization_memory = arguments.Tensor(self.batch_size * self.board_count * constants.players_count, 1):zero()
    self.counterfactual_value_memory = arguments.Tensor(self.batch_size, constants.players_count, self.board_count, self.bucket_count):zero()
  end

  --computing bucket range in next street for both players at once
  self:_card_range_to_bucket_range(ranges:view(self.batch_size * constants.players_count, -1), self.next_round_extended_range:view(self.batch_size * constants.players_count, -1))
  self.range_normalization:sum(self.next_round_serialized_range, 2)
  local rn_view = self.range_normalization:view(self.batch_size, constants.players_count, self.board_count)
  for player = 1, constants.players_count do
    self.value_normalization[{{}, player, {}}]:copy(rn_view[{{}, 3 - player, {}}])
  end
  if use_memory then
    self.range_normalization_memory:add(self.value_normalization)
  end
  --eliminating division by zero
  self.range_normalization[torch.eq(self.range_normalization, 0)] = 1
  self.next_round_serialized_range:cdiv(self.range_normalization:expandAs(self.next_round_serialized_range))
  local serialized_range_by_player = self.next_round_serialized_range:view(self.batch_size, constants.players_count, self.board_count, self.bucket_count)
  for player = 1, constants.players_count do 
    local player_range_index = {(player -1) * self.bucket_count + 1, player * self.bucket_count}
    self.next_round_inputs[{{}, {}, player_range_index}]:copy(self.next_round_extended_range[{{},player, {}}])
  end

  --usning nn to compute values 
  local serialized_inputs_view= self.next_round_inputs:view(self.batch_size * self.board_count, -1)
  local serialized_values_view= self.next_round_values:view(self.batch_size * self.board_count, -1)

  --computing value in the next round
  self.nn:get_value(serialized_inputs_view, serialized_values_view)

  --normalizing values back according to the orginal range sum
  local normalization_view = self.value_normalization:view(self.batch_size, constants.players_count, self.board_count, 1):transpose(2,3)
  self.next_round_values:cmul(normalization_view:expandAs(self.next_round_values))
    
  self.transposed_next_round_values:copy(self.next_round_values:transpose(3,2))
  --remembering the values for the next round
  if use_memory then
    self.counterfactual_value_memory:add(self.transposed_next_round_values)
  end
  --translating bucket values back to the card values
  self:_bucket_value_to_card_value(self.transposed_next_round_values:view(self.batch_size * constants.players_count, -1), values:view(self.batch_size * constants.players_count, -1)) 
end

--- Gives the average counterfactual values on the given board across previous
-- calls to @{get_value}.
-- 
-- Used to update opponent counterfactual values during re-solving after board
-- cards are dealt.
-- @param board a non-empty vector of board cards
-- @param values a tensor in which to store the values
function NextRoundValue:get_value_on_board(board, values)
  --check if we have evaluated correct number of iterations
  assert(self.iter == arguments.cfr_iters )
  local batch_size = values:size(1)
  assert(batch_size == self.batch_size)

  self:_prepare_next_round_values()

  self:_bucket_value_to_card_value_on_board(board, self.counterfactual_value_memory, values)
end

--- Normalizes the counterfactual values remembered between @{get_value} calls
-- so that they are an average rather than a sum.
-- @local
function NextRoundValue:_prepare_next_round_values()

  assert(self.iter == arguments.cfr_iters )

  --do nothing if already prepared
  if self._values_are_prepared then
    return
  end

  --eliminating division by zero
  self.range_normalization_memory[torch.eq(self.range_normalization_memory, 0)] = 1
  local serialized_memory_view = self.counterfactual_value_memory:view(-1, self.bucket_count) 
  serialized_memory_view:cdiv(self.range_normalization_memory:expandAs(serialized_memory_view))

  self._values_are_prepared = true
end



