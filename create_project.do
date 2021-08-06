file mkdir C:/Alephium/Git/fpga-miner/Blake3Modelsim

project new C:/Alephium/Git/fpga-miner/Blake3Modelsim Blake3Modelsim work

project addfile ../src/defines.sv 
project addfile ../src/G_function.v
project addfile ../src/G_round.v
project addfile ../src/QuadG.sv
project addfile ../src/HashGen.sv
project addfile ../tb/HashGenTB.sv