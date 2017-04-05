--- Various constants used in DeepStack.
-- @module constants

local constants = {}

--- the number of players in the game
constants.players_count = 2
--- the number of betting rounds in the game
constants.streets_count = 2

--- IDs for each player and chance
-- @field chance `0`
-- @field P1 `1`
-- @field P2 `2`
constants.players = {}
constants.players.chance = 0
constants.players.P1 = 1
constants.players.P2 = 2

--- IDs for terminal nodes (either after a fold or call action) and nodes that follow a check action
-- @field terminal_fold (terminal node following fold) `-2`
-- @field terminal_call (terminal node following call) `-1`
-- @field chance_node (node for the chance player) `0`
-- @field check (node following check) `-1`
-- @field inner_node (any other node) `2`
constants.node_types = {}
constants.node_types.terminal_fold = -2
constants.node_types.terminal_call = -1
constants.node_types.check = -1
constants.node_types.chance_node = 0
constants.node_types.inner_node = 1

--- IDs for fold and check/call actions
-- @field fold `-2`
-- @field ccall (check/call) `-1`
constants.actions = {}
constants.actions.fold = -2
constants.actions.ccall = -1

--- String representations for actions in the ACPC protocol
-- @field fold "`fold`"
-- @field ccall (check/call) "`ccall`"
-- @field raise "`raise`"
constants.acpc_actions = {}
constants.acpc_actions.fold = "fold"
constants.acpc_actions.ccall = "ccall"
constants.acpc_actions.raise = "raise"

return constants