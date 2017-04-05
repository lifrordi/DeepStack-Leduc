--- Script that generates training and validation files.
-- @see data_generation
-- @script main_data_generation
local arguments = require 'Settings.arguments'
local data_generation = require 'DataGeneration.data_generation'

data_generation:generate_data(arguments.train_data_count, arguments.valid_data_count)