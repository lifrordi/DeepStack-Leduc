--- Evaluates hand strength in Leduc Hold'em and variants.
-- 
-- Works with hands which contain two or three cards, but assumes that
-- the deck contains no more than two cards of each rank (so three-of-a-kind
-- is not a possible hand).
-- 
-- Hand strength is given as a numerical value, where a lower strength means
-- a stronger hand: high pair < low pair < high card < low card
-- @module evaluator

require 'torch'
require 'math'
local game_settings = require 'Settings.game_settings'
local card_to_string = require 'Game.card_to_string_conversion'
local card_tools = require 'Game.card_tools'
local arguments = require 'Settings.arguments'

local M = {}

--- Gives a strength representation for a hand containing two cards.
-- @param hand_ranks the rank of each card in the hand
-- @return the strength value of the hand
-- @local
function M:evaluate_two_card_hand(hand_ranks)
  --check for the pair 
  local hand_value = nil 
  if hand_ranks[1] == hand_ranks[2] then
    --hand is a pair
    hand_value = hand_ranks[1]
  else
    --hand is a high card    
    hand_value = hand_ranks[1] * game_settings.rank_count + hand_ranks[2]    
  end
  return hand_value
end

--- Gives a strength representation for a hand containing three cards.
-- @param hand_ranks the rank of each card in the hand
-- @return the strength value of the hand
-- @local
function M:evaluate_three_card_hand(hand_ranks)
  local hand_value = nil
  --check for the pair 
  if hand_ranks[1] == hand_ranks[2] then 
    --paired hand, value of the pair goes first, value of the kicker goes second
    hand_value = hand_ranks[1] * game_settings.rank_count + hand_ranks[3]
  elseif hand_ranks[2] == hand_ranks[3] then 
    --paired hand, value of the pair goes first, value of the kicker goes second
    hand_value = hand_ranks[2] * game_settings.rank_count + hand_ranks[1]
  else
    --hand is a high card    
    hand_value = hand_ranks[1] * game_settings.rank_count * game_settings.rank_count + hand_ranks[2] * game_settings.rank_count + hand_ranks[3]   
  end
  return hand_value
end

--- Gives a strength representation for a two or three card hand.
-- @param hand a vector of two or three cards
-- @param[opt] impossible_hand_value the value to return if the hand is invalid
-- @return the strength value of the hand, or `impossible_hand_value` if the 
-- hand is invalid
function M:evaluate(hand, impossible_hand_value)
  assert(hand:max() <= game_settings.card_count and hand:min() > 0, 'hand does not correspond to any cards' )
  impossible_hand_value = impossible_hand_value or -1
  if not card_tools:hand_is_possible(hand) then
    return impossible_hand_value
  end
  --we are not interested in the hand suit - we will use ranks instead of cards
  local hand_ranks = hand:clone()
  for i = 1, hand_ranks:size(1) do 
    hand_ranks[i] = card_to_string:card_to_rank(hand_ranks[i])
  end
  hand_ranks = hand_ranks:sort()
  if hand:size(1) == 2 then
    return self:evaluate_two_card_hand(hand_ranks)
  elseif hand:size(1) == 3 then
    return self:evaluate_three_card_hand(hand_ranks)
  else
    assert(false, 'unsupported size of hand!' )
  end
end

--- Gives strength representations for all private hands on the given board.
-- @param board a possibly empty vector of board cards
-- @param impossible_hand_value the value to assign to hands which are invalid 
-- on the board
-- @return a vector containing a strength value or `impossible_hand_value` for
-- every private hand
function M:batch_eval(board, impossible_hand_value)
  local hand_values = arguments.Tensor(game_settings.card_count):fill(-1)
  if board:dim() == 0 then 
    for hand = 1, game_settings.card_count do 
      hand_values[hand] = math.floor((hand -1 ) / game_settings.suit_count ) + 1
    end
  else
    local board_size = board:size(1)
    assert(board_size == 1 or board_size == 2, 'Incorrect board size for Leduc' )
    local whole_hand = arguments.Tensor(board_size + 1)
    whole_hand[{{1, -2}}]:copy(board)
    for card = 1, game_settings.card_count do 
      whole_hand[-1] = card; 
      hand_values[card] = self:evaluate(whole_hand, impossible_hand_value)
    end 
  end
  return hand_values
end

return M