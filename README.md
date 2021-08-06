## Installing ModelSim

Go to the intelFpga 
[website](https://fpgasoftware.intel.com/20.1.1/?edition=lite&product=modelsim_ae&platform=windows#tabs-2).
Install it!

## Creating project and running simulation

Start ModelSim and run the following commands:

    do C:/Alephium/Git/fpga-miner/create_project.do
    project compileall
    vsim work.HashGenTB
    do C:/Alephium/Git/fpga-miner/wave.do
    run -all

