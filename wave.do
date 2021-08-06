#System
add wave -noupdate -expand -group System -label CLK -radix binary sim:/HashGenTB/clk

#Inputs
add wave -noupdate -expand -group Inputs -label Start -radix binary sim:/HashGenTB/strt
add wave -noupdate -expand -group Inputs -label BlockLength -radix hexadecimal sim:/HashGenTB/DUT/BL_I
add wave -noupdate -expand -group Inputs -label ChunkStart -radix binary sim:/HashGenTB/DUT/CS_flg_I
add wave -noupdate -expand -group Inputs -label ChunkEnd -radix binary sim:/HashGenTB/DUT/CE_flg_I
add wave -noupdate -expand -group Inputs -label Root -radix binary sim:/HashGenTB/DUT/ROOT_flg_I
add wave -noupdate -expand -group Inputs -label ChainingValue -radix hexadecimal sim:/HashGenTB/DUT/H_I
add wave -noupdate -expand -group Inputs -label MessageWords -radix hexadecimal sim:/HashGenTB/M_I

#Outputs
add wave -noupdate -expand -group Outputs -label Valid -radix binary sim:/HashGenTB/vld
add wave -noupdate -expand -group Outputs -label Hash -radix hexadecimal sim:/HashGenTB/H_O

add wave -noupdate -expand -label CC_Counter -radix decimal sim:/HashGenTB/clk_cntr