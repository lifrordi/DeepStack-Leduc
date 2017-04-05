--- Converts between DeepStack's internal representation and the ACPC protocol
-- used to communicate with the dealer.
-- 
-- For details on the ACPC protocol, see 
-- <http://www.computerpokercompetition.org/downloads/documents/protocols/protocol.pdf>.
-- @classmod protocol_to_node
local arguments = require 'Settings.arguments'
local constants = require "Settings.constants"
local tools = require 'tools'
local card_to_string = require "Game.card_to_string_conversion"

local ACPCProtocolToNode = torch.class('ACPCProtocolToNode')

--- Constructor
function ACPCProtocolToNode:_init()
end

--- Checks if a string starts with a given substring.
-- @param string the string to check
-- @param start the substring to check as the prefix of `String`
-- @return `true` if `start` is a prefix of `string`
-- @local
function string.starts(string,start)
   return string.sub(string,1,string.len(start))==start
end

--- Parses a list of actions from a string representation.
-- @param actions a string representing a series of actions in ACPC format
-- @return a list of actions, each of which is a table with fields:
-- 
-- * `action`: an element of @{constants.acpc_actions}
-- 
-- * `raise_amount`: the number of chips raised (if `action` is raise)
-- @local
function ACPCProtocolToNode:_parse_actions(actions)

  local out = {}
  local actions_remainder = actions

  while actions_remainder ~= '' do
  
    local parsed_chunk = ''
    if string.starts(actions_remainder, "c") then
      table.insert(out, {action = constants.acpc_actions.ccall})
      parsed_chunk = "c"
    elseif string.starts(actions_remainder, "r") then
      local _
      local raise_amount
      _, _, raise_amount = string.find(actions_remainder, "^r(%d*).*")
      raise_amount = tonumber(raise_amount)
      table.insert(out, {action = constants.acpc_actions.raise, raise_amount = raise_amount})
      parsed_chunk = "r" .. raise_amount
    elseif string.starts(actions_remainder, "f") then
      table.insert(out, {action = constants.acpc_actions.fold})
      parsed_chunk = "f"
    else
      assert(false)
    end    
    
    assert(#parsed_chunk > 0)
    actions_remainder = string.sub(actions_remainder, #parsed_chunk + 1)
  end
  
  
  return out
end

--- Parses a set of parameters that represent a poker state, from a string
-- representation.
-- @param state a string representation of a poker state in ACPC format
-- @return a table of state parameters, containing the fields:
-- 
-- * `position`: the acting player
-- 
-- * `hand_id`: a numerical id for the hand
-- 
-- * `actions`: a list of actions which reached the state, for each 
-- betting round - each action is a table with fields:
-- 
--     * `action`: an element of @{constants.acpc_actions}
-- 
--     * `raise_amount`: the number of chips raised (if `action` is raise)
-- 
-- * `actions_raw`: a string representation of actions for each betting round
-- 
-- * `board`: a string representation of the board cards
-- 
-- * `hand_p1`: a string representation of the first player's private hand
-- 
-- * `hand_p2`: a string representation of the second player's private hand
-- @local
function ACPCProtocolToNode:_parse_state(state)

  --MATCHSTATE:0:99:cc/r8146c/cc/cc:4cTs|Qs9s/9h5d8d/6c/6d
  local cards
  local actions
  local position
  local hand_id
  local _
 
    _, _, position, hand_id, actions, cards = string.find(state, "^MATCHSTATE:(%d):(%d*):([^:]*):(.*)")
  
  print('position: ', position)
  print('actions: ', actions)
  print('cards: ', cards)
  
  --cc/r8146c/cc/cc
  local preflop_actions
  local flop_actions
    _, _, preflop_actions, flop_actions = string.find(actions, "([^/]*)/?([^/]*)")
  
  print('preflop_actions: ', preflop_actions)
  print('flop_actions: ', flop_actions)
  
  --4cTs|Qs9s/9h5d8d/6c/6d
  local hand_p1
  local hand_p2
  local flop
   
   _, _, hand_p1, hand_p2, flop = string.find(cards, "([^|]*)|([^/]*)/?([^/]*)")
  print('hand_sb: ', hand_sb)
  print('hand_bb: ', hand_bb)
  print('flop: ', flop)

  local out = {}
  
  out.position = position
  out.hand_id = hand_id
  
  out.actions = {}
  out.actions[1] = self:_parse_actions(preflop_actions)
  out.actions[2] = self:_parse_actions(flop_actions)
  
  out.actions_raw = {}
  out.actions_raw[1] = preflop_actions
  out.actions_raw[2] = flop_actions
  
  out.board = flop
  
  out.hand_p1 = hand_p1
  out.hand_p2 = hand_p2
  
  return out
end

--- Processes a list of actions for a betting round.
-- @param actions a list of actions (see @{_parse_actions})
-- @param street the betting round on which the actions takes place
-- @param all_actions A list which the actions are appended to. Fields `player`,
-- `street`, and `index` are added to each action.
-- @local
function ACPCProtocolToNode:_convert_actions_street(actions, street, all_actions)

  local street_first_player = constants.players.P1

  for i=1, #actions do
    local acting_player = -1
    if i % 2 == 1 then
      acting_player = street_first_player
    else
      acting_player = 3 - street_first_player
    end
    
    local action = actions[i]
    action.player = acting_player
    action.street = street
    action.index = #all_actions + 1
    
    table.insert(all_actions, action)
  end
end

--- Processes all actions.
-- @param actions a list of actions for each betting round
-- @return a of list actions, processed with @{_convert_actions_street} and
-- concatenated
-- @local
function ACPCProtocolToNode:_convert_actions(actions)
  
  local all_actions = {}

  for street = 1, 2 do
    self:_convert_actions_street(actions[street], street, all_actions)
  end
  
  return all_actions
end

--- Further processes a parsed state into a format understandable by DeepStack.
-- @param parsed_state a parsed state returned by @{_parse_state}
-- @return a table of state parameters, with the fields:
-- 
-- * `position`: which player DeepStack is (element of @{constants.players})
-- 
-- * `current_street`: the current betting round
-- 
-- * `actions`: a list of actions which reached the state, for each 
-- betting round - each action is a table with fields:
-- 
--     * `action`: an element of @{constants.acpc_actions}
-- 
--     * `raise_amount`: the number of chips raised (if `action` is raise)
-- 
-- * `actions_raw`: a string representation of actions for each betting round
-- 
-- * `all_actions`: a concatenated list of all of the actions in `actions`,
-- with the following fields added:
-- 
--     * `player`: the player who made the action
-- 
--     * `street`: the betting round on which the action was taken
-- 
--     * `index`: the index of the action in `all_actions`
-- 
-- * `board`: a string representation of the board cards
-- 
-- * `hand_id`: a numerical id for the current hand
-- 
-- * `hand_string`: a string representation of DeepStack's private hand
-- 
-- * `hand_id`: a numerical representation of DeepStack's private hand
-- 
-- * `acting_player`: which player is acting (element of @{constants.players})
-- 
-- * `bet1`, `bet2`: the number of chips committed by each player
-- @local
function ACPCProtocolToNode:_process_parsed_state(parsed_state)
  
  local out = {}
  --1.0 figure out the current street
  local current_street = 1
  
  if parsed_state.board ~= '' then
    current_street = 2
  end
  
  print('current_street: ', current_street)
  
  
  --2.0 convert actions to player actions
  local all_actions
  all_actions = self:_convert_actions(parsed_state.actions)
  
  print('all_actions: ', tools:table_to_string(all_actions))
  
  --3.0 current board
  local board = parsed_state.board  
  print('board: ', board)
  
  --in protocol 0=BB 1=SB, need to convert to our representation
  out.position = parsed_state.position + 1
  out.current_street = current_street
  out.actions = parsed_state.actions
  out.actions_raw = parsed_state.actions_raw
  out.all_actions = all_actions
  out.board = board
  out.hand_number = parsed_state.hand_id
  
  if out.position == constants.players.P1 then
    out.hand_string = parsed_state.hand_p1
  else
    out.hand_string = parsed_state.hand_p2  
  end
  out.hand_id = card_to_string:string_to_card(out.hand_string)
  
  local acting_player = self:_get_acting_player(out)
  print('acting_player: ', acting_player)
  out.acting_player = acting_player
  
  --5.0 compute bets
  local bet1
  local bet2
  bet1, bet2 = self:_compute_bets(out)
  assert(bet1 <= bet2)
  
  if out.position == constants.players.P1 then
    out.bet1 = bet1
    out.bet2 = bet2
  else
    out.bet1 = bet2
    out.bet2 = bet1
  end

  return out
end

--- Computes the number of chips committed by each player at a state.
-- @param processed_state a table containing the fields returned by
-- @{_process_parsed_state}, except for `bet1` and `bet2`
-- @return the number of chips committed by the first player
-- @return the number of chips committed by the second player
-- @local
function ACPCProtocolToNode:_compute_bets(processed_state)
  
  if processed_state.acting_player == -1 then
    return -1, -1
  end
  

  local first_p1_action = {action = constants.acpc_actions.raise, raise_amount = arguments.ante, player = constants.players.P1, street = 1}
  local first_p2_action = {action = constants.acpc_actions.raise, raise_amount = arguments.ante, player = constants.players.P2, street = 2}
  
  local last_action = first_p1_action
  local prev_last_action = first_p2_action
  
  local prev_last_bet = first_p2_action
  
  for i = 1, #processed_state.all_actions do
    
    local action = processed_state.all_actions[i]
    assert(action.player == constants.players.P1 or action.player == constants.players.P2)
    
    prev_last_action = last_action
    last_action = action

    if action.action == constants.acpc_actions.raise and i <= (#processed_state.all_actions - 2) then
      prev_last_bet = action
    end
  end
  
  local bet1 = nil
  local bet2 = nil
  
  if last_action.action == constants.acpc_actions.raise and prev_last_action.action == constants.acpc_actions.raise then
    bet1 = prev_last_action.raise_amount
    bet2 = last_action.raise_amount
  else
    
    if last_action.action == constants.acpc_actions.ccall and prev_last_action.action == constants.acpc_actions.ccall then
      bet1 = prev_last_bet.raise_amount
      bet2 = prev_last_bet.raise_amount
    else
    
      --either ccal/raise or raise/ccal situation
      assert(last_action.action.player ~= prev_last_action.player)
      
      --raise/ccall
      if last_action.action == constants.acpc_actions.ccall then
        assert(prev_last_action.action == constants.acpc_actions.raise and prev_last_action.raise_amount)
        bet1 = prev_last_action.raise_amount
        bet2 = prev_last_action.raise_amount
      else
      --call/raise
        
        assert(last_action.action == constants.acpc_actions.raise and last_action.raise_amount)
        bet1 = prev_last_bet.raise_amount
        bet2 = last_action.raise_amount
      end
    end
  end

  assert(bet1)
  assert(bet2)

  print("bet1 :", bet1)
  print("bet2 :", bet2)
  
  return bet1, bet2
end

--- Gives the acting player at a given state.
-- @param processed_state a table containing the fields returned by
-- @{_process_parsed_state}, except for `acting_player`, `bet1`, and `bet2`
-- @return the acting player, as defined by @{constants.players}
-- @local
function ACPCProtocolToNode:_get_acting_player(processed_state)
  
  if #processed_state.all_actions == 0  then
    assert(processed_state.current_street == 1)
    return constants.players.P1
  end
  
  local last_action = processed_state.all_actions[#processed_state.all_actions]
  
  --has the street changed since the last action?
  if last_action.street ~= processed_state.current_street then
    return constants.players.P1
  end
  
  --is the hand over?
  if last_action.action == constants.acpc_actions.fold then
    return -1
  end
  
  if processed_state.current_street == 2 and #processed_state.actions[2] >= 2 and last_action.action == constants.acpc_actions.ccall then
    return -1  
  end
  
  --there are some actions on the current street
  --the acting player is the opponent of the one who made the last action
  return 3 - last_action.player
end

--- Turns a string representation of a poker state into a table understandable 
-- by DeepStack.
-- @param state a string representation of a poker state, in ACPC format
-- @return a table of state parameters, with the fields:
-- 
-- * `position`: which player DeepStack is (element of @{constants.players})
-- 
-- * `current_street`: the current betting round
-- 
-- * `actions`: a list of actions which reached the state, for each 
-- betting round - each action is a table with fields:
-- 
--     * `action`: an element of @{constants.acpc_actions}
-- 
--     * `raise_amount`: the number of chips raised (if `action` is raise)
-- 
-- * `actions_raw`: a string representation of actions for each betting round
-- 
-- * `all_actions`: a concatenated list of all of the actions in `actions`,
-- with the following fields added:
-- 
--     * `player`: the player who made the action
-- 
--     * `street`: the betting round on which the action was taken
-- 
--     * `index`: the index of the action in `all_actions`
-- 
-- * `board`: a string representation of the board cards
-- 
-- * `hand_id`: a numerical id for the current hand
-- 
-- * `hand_string`: a string representation of DeepStack's private hand
-- 
-- * `hand_id`: a numerical representation of DeepStack's private hand
-- 
-- * `acting_player`: which player is acting (element of @{constants.players})
-- 
-- * `bet1`, `bet2`: the number of chips committed by each player
function ACPCProtocolToNode:parse_state(state)
 
  local parsed_state = self:_parse_state(state)
  local processed_state = self:_process_parsed_state(parsed_state)
  
  return processed_state
end

--- Gets a representation of the public tree node which corresponds to a
-- processed state.
-- @param processed_state a processed state representation returned by 
-- @{parse_state}
-- @return a table representing a public tree node, with the fields:
-- 
-- * `street`: the current betting round
-- 
-- * `board`: a (possibly empty) vector of board cards
-- 
-- * `current_player`: the currently acting player
-- 
-- * `bets`: a vector of chips committed by each player
function ACPCProtocolToNode:parsed_state_to_node(processed_state)
  local node = {}  
  
  node.street = processed_state.current_street
  node.board = card_to_string:string_to_board(processed_state.board)
  node.current_player = processed_state.acting_player
  node.bets = arguments.Tensor{processed_state.bet1, processed_state.bet2}
  
  return node  
end

--- Converts an action taken by DeepStack into a string representation.
-- @param adviced_action the action that DeepStack chooses to take, with fields
-- 
-- * `action`: an element of @{constants.acpc_actions}
-- 
-- * `raise_amount`: the number of chips to raise (if `action` is raise)
-- @return a string representation of the action
-- @local
function ACPCProtocolToNode:_bet_to_protocol_action(adviced_action)
  
  if adviced_action.action == constants.acpc_actions.ccall then
    return "c"
  elseif adviced_action.action == constants.acpc_actions.fold then
    return "f"
  elseif adviced_action.action == constants.acpc_actions.raise then
    return "r" .. adviced_action.raise_amount
  else
    assert(false)
  end
end

--- Generates a message to send to the ACPC protocol server, given DeepStack's
-- chosen action.
-- @param last_message the last state message sent by the server
-- @param adviced_action the action that DeepStack chooses to take, with fields
-- 
-- * `action`: an element of @{constants.acpc_actions}
-- 
-- * `raise_amount`: the number of chips to raise (if `action` is raise)
-- @return a string messsage in ACPC format to send to the server
function ACPCProtocolToNode:action_to_message(last_message, adviced_action)
  
  local out = last_message
  
  local protocol_action = self:_bet_to_protocol_action(adviced_action)
  
  out = out  .. ":" .. protocol_action
  
  return out
end
