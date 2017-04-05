--- Evaluates player equities at terminal nodes of the game's public tree.
-- @classmod terminal_equity

require 'torch'
local evaluator = require 'Game.Evaluation.evaluator'
local game_settings = require 'Settings.game_settings'
local arguments = require 'Settings.arguments'
local card_tools = require 'Game.card_tools'

local TerminalEquity = torch.class('TerminalEquity')

--- Constructor
function TerminalEquity:__init()
end

--- Constructs the matrix that turns player ranges into showdown equity.
-- 
-- Gives the matrix `A` such that for player ranges `x` and `y`, `x'Ay` is the equity
-- for the first player when no player folds.
-- 
-- @param board_cards a non-empty vector of board cards
-- @param call_matrix a tensor where the computed matrix is stored
-- @local
function TerminalEquity:get_last_round_call_matrix(board_cards, call_matrix)
  assert(board_cards:size(1) == 1 or board_cards:size(1) == 2, 'Only Leduc and extended Leduc are now supported' )
  
  local strength = evaluator:batch_eval(board_cards);
  --handling hand stregths (winning probs);
  local strength_view_1 = strength:view(game_settings.card_count, 1):expandAs(call_matrix)
  local strength_view_2 = strength:view(1, game_settings.card_count):expandAs(call_matrix)

  call_matrix:copy(torch.gt(strength_view_1, strength_view_2))
  call_matrix:csub(torch.lt(strength_view_1, strength_view_2):typeAs(call_matrix))

  self:_handle_blocking_cards(call_matrix, board_cards);
end

--- Zeroes entries in an equity matrix that correspond to invalid hands.
-- 
-- A hand is invalid if it shares any cards with the board.
--
-- @param equity_matrix the matrix to modify
-- @param board a possibly empty vector of board cards
-- @local
function TerminalEquity:_handle_blocking_cards(equity_matrix, board)
  local possible_hand_indexes = card_tools:get_possible_hand_indexes(board);
  local possible_hand_matrix = possible_hand_indexes:view(1, game_settings.card_count):expandAs(equity_matrix);
  equity_matrix:cmul(possible_hand_matrix);
  possible_hand_matrix = possible_hand_indexes:view(game_settings.card_count,1):expandAs(equity_matrix);
  equity_matrix:cmul(possible_hand_matrix);
end

--- Sets the evaluator's fold matrix, which gives the equity for terminal
-- nodes where one player has folded.
-- 
-- Creates the matrix `B` such that for player ranges `x` and `y`, `x'By` is the equity
-- for the player who doesn't fold
-- @param board a possibly empty vector of board cards
-- @local
function TerminalEquity:_set_fold_matrix(board)
  self.fold_matrix = arguments.Tensor(game_settings.card_count, game_settings.card_count);
  self.fold_matrix:fill(1);
  --setting cards that block each other to zero - exactly elements on diagonal in leduc variants
  self.fold_matrix:csub(torch.eye(game_settings.card_count):typeAs(self.fold_matrix))
  self:_handle_blocking_cards(self.fold_matrix, board);
end;

--- Sets the evaluator's call matrix, which gives the equity for terminal
-- nodes where no player has folded.
-- 
-- For nodes in the last betting round, creates the matrix `A` such that for player ranges
-- `x` and `y`, `x'Ay` is the equity for the first player when no player folds. For nodes
-- in the first betting round, gives the weighted average of all such possible matrices.
--
-- @param board a possibly empty vector of board cards
-- @local
function TerminalEquity:_set_call_matrix(board)
  local street = card_tools:board_to_street(board);
  self.equity_matrix = arguments.Tensor(game_settings.card_count, game_settings.card_count):zero();
  
  if street == 1 then
    --iterate through all possible next round streets
    local next_round_boards = card_tools:get_second_round_boards();
    local boards_count = next_round_boards:size(1);
    local next_round_equity_matrix = arguments.Tensor(game_settings.card_count, game_settings.card_count);
    for board = 1, boards_count do
      self:get_last_round_call_matrix(next_round_boards[board], next_round_equity_matrix);
      self.equity_matrix:add(next_round_equity_matrix);
    end;
    --averaging the values in the call matrix
    local weight_constant = game_settings.board_card_count == 1 and 1/(game_settings.card_count -2) or 2/((game_settings.card_count -2) * (game_settings.card_count -3 ))
    self.equity_matrix:mul(weight_constant);
  elseif  street == 2  then
    --for last round we just return the matrix
    self:get_last_round_call_matrix(board, self.equity_matrix);
  else
    --impossible street
    assert(false, 'impossible street');
  end
end

--- Sets the board cards for the evaluator and creates its internal data structures.
-- @param board a possibly empty vector of board cards
function TerminalEquity:set_board(board)
    self:_set_call_matrix(board);
    self:_set_fold_matrix(board);
end

--- Computes (a batch of) counterfactual values that a player achieves at a terminal node
-- where no player has folded.
-- 
-- @{set_board} must be called before this function.
--
-- @param ranges a batch of opponent ranges in an NxK tensor, where N is the batch size
-- and K is the range size
-- @param result a NxK tensor in which to save the cfvs
function TerminalEquity:call_value( ranges, result )
  result:mm(ranges, self.equity_matrix);
end

--- Computes (a batch of) counterfactual values that a player achieves at a terminal node
-- where a player has folded.
-- 
-- @{set_board} must be called before this function.
--
-- @param ranges a batch of opponent ranges in an NxK tensor, where N is the batch size
-- and K is the range size
-- @param result A NxK tensor in which to save the cfvs. Positive cfvs are returned, and
-- must be negated if the player in question folded.
function TerminalEquity:fold_value( ranges, result )
  result:mm(ranges, self.fold_matrix);
end

--- Returns the matrix which gives showdown equity for any ranges.
-- 
-- @{set_board} must be called before this function.
--
-- @return For nodes in the last betting round, the matrix `A` such that for player ranges
-- `x` and `y`, `x'Ay` is the equity for the first player when no player folds. For nodes
-- in the first betting round, the weighted average of all such possible matrices.
function TerminalEquity:get_call_matrix()
  return self.equity_matrix
end

--- Computes the counterfactual values that both players achieve at a terminal node
-- where no player has folded.
-- 
-- @{set_board} must be called before this function.
--
-- @param ranges a 2xK tensor containing ranges for each player (where K is the range size)
-- @param result a 2xK tensor in which to store the cfvs for each player
function TerminalEquity:tree_node_call_value( ranges, result )
  assert(ranges:dim() == 2)
  assert(result:dim() == 2)
  self:call_value(ranges[1]:view(1,  -1), result[2]:view(1,  -1)) 
  self:call_value(ranges[2]:view(1,  -1), result[1]:view(1,  -1))
end

--- Computes the counterfactual values that both players achieve at a terminal node
-- where either player has folded.
--
-- @{set_board} must be called before this function.
--
-- @param ranges a 2xK tensor containing ranges for each player (where K is the range size)
-- @param result a 2xK tensor in which to store the cfvs for each player
-- @param folding_player which player folded
function TerminalEquity:tree_node_fold_value( ranges, result, folding_player )
  assert(ranges:dim() == 2)
  assert(result:dim() == 2)
  self:fold_value(ranges[1]:view(1,  -1), result[2]:view(1,  -1)) 
  self:fold_value(ranges[2]:view(1,  -1), result[1]:view(1,  -1))
  
  result[folding_player]:mul(-1)
end


TerminalEquity:set_board(torch.Tensor())