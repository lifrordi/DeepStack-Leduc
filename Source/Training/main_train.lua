--- Script that trains the neural network.
-- 
-- Uses data previously generated with @{data_generation_call}.
-- @script main_train

local nnBuilder = require 'Nn.net_builder'
require 'Training.data_stream'
local train = require 'Training.train'
local arguments = require 'Settings.arguments'

  
--build the network
local network = nnBuilder:build_net()

if arguments.gpu then
  network = network:cuda()
end

local data_stream = DataStream()
train:train(network, data_stream, arguments.epoch_count)
