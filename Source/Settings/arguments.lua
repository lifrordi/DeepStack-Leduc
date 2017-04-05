--- Parameters for DeepStack.
--@module arguments

local torch = require 'torch'

torch.setdefaulttensortype('torch.FloatTensor')

local params = {}

--- whether to run on GPU
params.gpu = false
--- list of pot-scaled bet sizes to use in tree
-- @field params.bet_sizing
params.bet_sizing = {1}
--- server running the ACPC dealer
params.acpc_server = "localhost"
--- server port running the ACPC dealer
params.acpc_server_port = 20000
--- the number of betting rounds in the game
params.streets_count = 2
--- the tensor datatype used for storing DeepStack's internal data
params.Tensor = torch.FloatTensor
--- the directory for data files
params.data_directory = '../Data/'
--- the size of the game's ante, in chips
params.ante = 100
--- the size of each player's stack, in chips
params.stack = 1200
--- the number of iterations that DeepStack runs CFR for
params.cfr_iters = 1000
--- the number of preliminary CFR iterations which DeepStack doesn't factor into the average strategy (included in cfr_iters)
params.cfr_skip_iters = 500
--- how many poker situations are solved simultaneously during data generation
params.gen_batch_size = 10
--- how many poker situations are used in each neural net training batch
params.train_batch_size = 100
--- path to the solved poker situation data used to train the neural net
params.data_path = '../Data/TrainSamples/PotBet/'
--- path to the neural net model
params.model_path = '../Data/Models/PotBet/'
--- the name of the neural net file
params.value_net_name = 'final'
--- the neural net architecture
params.net = '{nn.Linear(input_size, 50), nn.PReLU(), nn.Linear(50, output_size)}'
--- how often to save the model during training
params.save_epoch = 2
--- how many epochs to train for
params.epoch_count = 10
--- how many solved poker situations are generated for use as training examples
params.train_data_count = 100
--- how many solved poker situations are generated for use as validation examples
params.valid_data_count = 100
--- learning rate for neural net training
params.learning_rate = 0.001


assert(params.cfr_iters > params.cfr_skip_iters)
if params.gpu then
  require 'cutorch'
  params.Tensor = torch.CudaTensor
end

return params