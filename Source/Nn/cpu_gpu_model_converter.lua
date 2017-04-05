--- Generates a neural net model in CPU format from a neural net model saved
-- in GPU format.
-- @script cpu_gpu_model_converter

require 'cunn'
local arguments = require 'Settings.arguments'

--- Generates a neural net model in CPU format from a neural net model saved
-- in GPU format.
-- @param gpu_model_path the prefix of the path to the gpu model, which is
-- appended with `_gpu.info` and `_gpu.model`
local function convert_gpu_to_cpu(gpu_model_path)    
  local info = torch.load(gpu_model_path .. '_gpu.info')  
  assert(info.gpu)
  info.gpu = false
    
  local model = torch.load(gpu_model_path .. '_gpu.model')
  model = model:float()
  
  torch.save(gpu_model_path .. '_cpu.info', info)
  torch.save(gpu_model_path .. '_cpu.model', model)  
end

--- Generates a neural net model in GPU format from a neural net model saved
-- in CPU format.
-- @param cpu_model_path the prefix of the path to the cpu model, which is
-- appended with `_cpu.info` and `_cpu.model`
local function convert_cpu_to_gpu(cpu_model_path)
  
  local info = torch.load(cpu_model_path .. '_cpu.info')  
  assert(not info.gpu)
  info.gpu = true
    
  local model = torch.load(cpu_model_path .. '_cpu.model')
  model = model:cuda()
  
  torch.save(cpu_model_path .. '_gpu.info', info)
  torch.save(cpu_model_path .. '_gpu.model', model)  
end


convert_gpu_to_cpu('../Data/Models/PotBet/final')