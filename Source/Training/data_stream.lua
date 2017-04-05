--- Handles the data used for neural net training and validation.
-- @classmod data_stream

require 'torch'
local arguments = require 'Settings.arguments'
local DataStream = torch.class('DataStream')

--- Constructor.
-- 
-- Reads the data from training and validation files generated with
-- @{data_generation_call.generate_data}.
function DataStream:__init()
  --loadind valid data
  self.data = {}
  local valid_prefix = arguments.data_path .. 'valid'
  self.data.valid_mask= torch.load(valid_prefix .. '.mask')
  self.data.valid_mask= self.data.valid_mask:repeatTensor(1,2)
  self.data.valid_targets = torch.load(valid_prefix .. '.targets')
  self.data.valid_inputs = torch.load(valid_prefix .. '.inputs')
  self.valid_data_count = self.data.valid_inputs:size(1)
  assert(self.valid_data_count >= arguments.train_batch_size, 'Validation data count has to be greater than a train batch size!')
  self.valid_batch_count = self.valid_data_count / arguments.train_batch_size
  --loading train data
  local train_prefix = arguments.data_path .. 'train'
  self.data.train_mask = torch.load(train_prefix .. '.mask')
  self.data.train_mask = self.data.train_mask:repeatTensor(1,2)
  self.data.train_inputs = torch.load(train_prefix .. '.inputs')
  self.data.train_targets = torch.load(train_prefix .. '.targets')
  self.train_data_count = self.data.train_inputs:size(1)
  assert(self.train_data_count >= arguments.train_batch_size, 'Training data count has to be greater than a train batch size!')
  self.train_batch_count = self.train_data_count / arguments.train_batch_size
  
  --transfering data to gpu if needed
  if arguments.gpu then 
    for key, value in pairs(self.data) do 
      self.data[key] = value:cuda()
    end
  end
end

--- Gives the number of batches of validation data.
-- 
-- Batch size is defined by @{arguments.train_batch_size}.
-- @return the number of batches
function DataStream:get_valid_batch_count()
  return self.valid_batch_count
end

--- Gives the number of batches of training data.
-- 
-- Batch size is defined by @{arguments.train_batch_size}
-- @return the number of batches
function DataStream:get_train_batch_count()
  return self.train_batch_count
end

--- Randomizes the order of training data.
-- 
-- Done so that the data is encountered in a different order for each epoch.
function  DataStream:start_epoch()
  --data are shuffled each epoch 
  local shuffle = torch.randperm(self.train_data_count):long()

  self.data.train_inputs = self.data.train_inputs:index(1, shuffle)
  self.data.train_targets = self.data.train_targets:index(1, shuffle)
  self.data.train_mask = self.data.train_mask:index(1, shuffle)
end

--- Returns a batch of data from a specified data set.
-- @param inputs the inputs set for the given data set
-- @param targets the targets set for the given data set
-- @param mask the masks set for the given data set
-- @param batch_index the index of the batch to return
-- @return the inputs set for the batch
-- @return the targets set for the batch
-- @return the masks set for the batch 
-- @local
function  DataStream:get_batch(inputs, targets, mask, batch_index)

  assert(inputs:size(1) == targets:size(1) and inputs:size(1) == mask:size(1))
  local batch_boundaries = {(batch_index - 1) * arguments.train_batch_size + 1,  batch_index * arguments.train_batch_size}
  local batch_table_index = {batch_boundaries, {}}
  local batch_inputs = inputs[batch_table_index]
  local batch_targets = targets[batch_table_index]
  local batch_mask = mask[batch_table_index]
  return batch_inputs, batch_targets, batch_mask
end

--- Returns a batch of data from the training set.
-- @param batch_index the index of the batch to return
-- @return the inputs set for the batch
-- @return the targets set for the batch
-- @return the masks set for the batch
function  DataStream:get_train_batch(batch_index)    
    return self:get_batch(self.data.train_inputs, self.data.train_targets, self.data.train_mask, batch_index)
end

--- Returns a batch of data from the validation set.
-- @param batch_index the index of the batch to return
-- @return the inputs set for the batch
-- @return the targets set for the batch
-- @return the masks set for the batch
function  DataStream:get_valid_batch(batch_index)
  return self:get_batch(self.data.valid_inputs, self.data.valid_targets, self.data.valid_mask, batch_index)
end