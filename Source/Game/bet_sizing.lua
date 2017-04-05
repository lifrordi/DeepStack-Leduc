--- Gives allowed bets during a game.
-- Bets are restricted to be from a list of predefined fractions of the pot.
-- @classmod bet_sizing

require 'math'
local arguments = require 'Settings.arguments'

local BetSizing = torch.class('BetSizing')

--- Constructor
-- @param pot_fractions a list of fractions of the pot which are allowed 
-- as bets, sorted in ascending order
function BetSizing:__init(pot_fractions)
  pot_fractions = pot_fractions or torch.Tensor{1}
  self.pot_fractions = pot_fractions
end

--- Gives the bets which are legal at a game state.
-- @param node a representation of the current game state, with fields:
-- 
-- * `bets`: the number of chips currently committed by each player
-- 
-- * `current_player`: the currently acting player
-- @return an Nx2 tensor where N is the number of new possible game states,
-- containing N sets of new commitment levels for each player
function BetSizing:get_possible_bets(node)
  local current_player = node.current_player
  assert(current_player == 1 or current_player == 2, 'Wrong player for bet size computation')
  local opponent = 3 - node.current_player 
  local opponent_bet = node.bets[opponent]

  assert(node.bets[current_player] <= opponent_bet)
  
  --compute min possible raise size 
  local max_raise_size = arguments.stack - opponent_bet
  local min_raise_size = opponent_bet - node.bets[current_player]
  min_raise_size = math.max(min_raise_size, arguments.ante)
  min_raise_size = math.min(max_raise_size, min_raise_size)
  
  if min_raise_size == 0 then 
    return arguments.Tensor()
  elseif min_raise_size == max_raise_size then
    local out = arguments.Tensor(1,2):fill(opponent_bet)
    out[1][current_player] = opponent_bet + min_raise_size
    return out
  else
     --iterate through all bets and check if they are possible
     local max_possible_bets_count = self.pot_fractions:size(1) + 1 --we can always go allin 
     local out = arguments.Tensor(max_possible_bets_count,2):fill(opponent_bet)
     
     --take pot size after opponent bet is called
     local pot = opponent_bet * 2
     local used_bets_count = 0;
     --try all pot fractions bet and see if we can use them 
     for i = 1, self.pot_fractions:size(1)  do 
       local raise_size = pot * self.pot_fractions[i]
       if raise_size >= min_raise_size and raise_size < max_raise_size then
         used_bets_count = used_bets_count + 1
         out[{used_bets_count, current_player}] = opponent_bet + raise_size
       end
     end
     --adding allin
     used_bets_count  = used_bets_count + 1
     assert(used_bets_count <= max_possible_bets_count)
     out[{used_bets_count, current_player}] = opponent_bet + max_raise_size
     return out[{{1, used_bets_count}, {}}]
  end  
end




