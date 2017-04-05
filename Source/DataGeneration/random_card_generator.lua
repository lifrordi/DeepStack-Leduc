--- Samples random card combinations.
-- @module random_card_generator

require "torch"
local M = {}
local game_settings = require 'Settings.game_settings'
local arguments = require 'Settings.arguments'

--- Samples a random set of cards.
-- 
-- Each subset of the deck of the correct size is sampled with 
-- uniform probability.
--
-- @param count the number of cards to sample
-- @return a vector of cards, represented numerically
function M:generate_cards( count )
  --marking all used cards
  local used_cards = torch.ByteTensor(game_settings.card_count):zero()
  
  local out = arguments.Tensor(count)
  --counter for generated cards
  local generated_cards_count = 0
  while(generated_cards_count < count) do
    local card = torch.random(1, game_settings.card_count)
    if ( used_cards[card] == 0 ) then 
      generated_cards_count = generated_cards_count + 1
      out[generated_cards_count] = card
      used_cards[card] = 1
    end
  end
  return out
end

return M
