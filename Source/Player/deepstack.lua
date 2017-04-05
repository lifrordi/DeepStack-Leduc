--- Performs the main loop for DeepStack.
-- @script deepstack

local arguments = require 'Settings.arguments'
require "ACPC.acpc_game"
require "Player.continual_resolving"

--1.0 create the ACPC game and connect to the server
local acpc_game = ACPCGame()
acpc_game:connect(arguments.acpc_server, arguments.acpc_server_port)

local continual_resolving = ContinualResolving()

local last_state = nil
local last_node = nil

--2.0 main loop that waits for a situation where we act and then chooses an action
while true do
  local state
  local node

  --2.1 blocks until it's our situation/turn
  state, node = acpc_game:get_next_situation()
  
  --did a new hand start?
  if not last_state or last_state.hand_number ~= state.hand_number or node.street < last_node.street then
    continual_resolving:start_new_hand(state)
  end

  --2.2 use continual resolving to find a strategy and make an action in the current node
  local adviced_action = continual_resolving:compute_action(node, state)

  --2.3 send the action to the dealer
  acpc_game:play_action(adviced_action)

  last_state = state
  last_node = node

  collectgarbage()
end