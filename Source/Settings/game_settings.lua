--- Game constants which define the game played by DeepStack.
-- @module game_settings

require 'torch'

--leduc defintion
local M = {}
--- the number of card suits in the deck
M.suit_count = 2
--- the number of card ranks in the deck
M.rank_count = 3
--- the total number of cards in the deck
M.card_count = M.suit_count * M.rank_count;
--- the number of public cards dealt in the game (revealed after the first
-- betting round)
M.board_card_count = 1;
--- the number of players in the game
M.player_count = 2

return M