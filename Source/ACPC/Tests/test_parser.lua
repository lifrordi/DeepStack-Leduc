require "ACPC.protocol_to_node"

local protocol_to_node = ACPCProtocolToNode()
local state = protocol_to_node:parse_state("MATCHSTATE:0:99:cc/r8146:Kh|/As")

local debug = 0