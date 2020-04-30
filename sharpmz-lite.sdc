## Generated SDC file "sharpmz-lite-div.out.sdc"

## Copyright (C) 2017  Intel Corporation. All rights reserved.
## Your use of Intel Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Intel Program License 
## Subscription Agreement, the Intel Quartus Prime License Agreement,
## the Intel MegaCore Function License Agreement, or other 
## applicable license agreement, including, without limitation, 
## that your use is for the sole purpose of programming logic 
## devices manufactured by Intel and sold by Intel or its 
## authorized distributors.  Please refer to the applicable 
## agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 17.0.2 Build 602 07/19/2017 SJ Lite Edition"

## DATE    "Wed Oct 31 10:26:38 2018"

##
## DEVICE  "5CSEBA6U23I7"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3


#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {FPGA_CLK1_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK1_50}]
create_clock -name {FPGA_CLK2_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK2_50}]
create_clock -name {FPGA_CLK3_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK3_50}]
create_clock -name {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk} -period 10.000 -waveform { 0.000 5.000 } [get_pins -compatibility_mode {*|h2f_user0_clk}]


#**************************************************************
# Create Generated Clock
#**************************************************************

derive_pll_clocks -create_base_clocks -use_tan_name

# create_generated_clock -name <name> -source <source> -divide_by <ratio: 2,4,8, ....> -duty_cycle 50.00 <generated_clk> 
# <name> a name assigned to the generate clock to be used in TQ analysis 
# <source> the reference to your master clock 
# <generated_clk> in your case this is the lpm_counter port where you pick the generated clock from
# create_generated_clock -name divclk_16mhz -divide_by 2 {lpm_counter0:Clock/2|lpm_counter:LPM_COUNTER_component|dffs[0]} 
#set all_enabled_registers ]
#set clock_enable_divide_by_n 4
#set_multicycle_path -setup $clock_enable_divide_by_n -from $all_enabled_registers -to $all_enabled_registers
#set_multicycle_path -hold  -from $all_enabled_registers -to $all_enabled_registers

#create_generated_clock -name {CK96M} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 192 -divide_by 100 \
#                       -master_clock {FPGA_CLK3_50} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]}] 
#create_generated_clock -name {CK64M} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 128 -divide_by 100 \
#                       -master_clock {FPGA_CLK3_50} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[1]}] 
#create_generated_clock -name {CK32M} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 64 -divide_by 100 \
#                       -master_clock {FPGA_CLK3_50} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[2]}] 
#create_generated_clock -name {CK16M} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 32 -divide_by 100 \
#                       -master_clock {FPGA_CLK3_50} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[3]}] 
#create_generated_clock -name {CK8M} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 16 -divide_by 100 \
#                       -master_clock {FPGA_CLK3_50} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[4]}] 
#create_generated_clock -name {CK4M} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 8 -divide_by 100 \
#                       -master_clock {FPGA_CLK3_50} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[5]}] 
#create_generated_clock -name {CK2M} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 4 -divide_by 100 \
#                       -master_clock {FPGA_CLK3_50} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[6]}] 
#
#create_generated_clock -name {CK56M75} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 591146 -divide_by 1000000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]}] 
#create_generated_clock -name {CK28M375} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 295573 -divide_by 1000000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[1]}] 
#create_generated_clock -name {CK14M1875} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 147786 -divide_by 1000000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[2]}] 
#create_generated_clock -name {CK7M09375} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 73893 -divide_by 1000000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[3]}] 
#create_generated_clock -name {CK3M546875} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 36947 -divide_by 1000000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[4]}] 
#
#create_generated_clock -name {CK85M86} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 894375 -divide_by 1000000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]}] 
#create_generated_clock -name {CK65M} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 67708 -divide_by 100000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[1]}] 
#create_generated_clock -name {CK25M175} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 26224 -divide_by 100000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[2]}] 
#create_generated_clock -name {CK17M734475} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 184734 -divide_by 1000000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[3]}] 
#create_generated_clock -name {CK8M867237} \
#                       -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] \
#                       -duty_cycle 50/1 -multiply_by 92367 -divide_by 1000000 \
#                       -master_clock {CK96M} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN03|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[4]}] 
#

# {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN01|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] 
#create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 8 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] 
#create_generated_clock -name {clk_2M} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -duty_cycle 50/1 -multiply_by 1 -divide_by 224 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} [get_registers {emu:emu|sharpmz:sharp_mz|clkgen:CLKGEN0|CK2Mi}] 
#create_generated_clock -name {clk_15611} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -duty_cycle 50/1 -multiply_by 1 -divide_by 28698 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} [get_registers {emu:emu|sharpmz:sharp_mz|clkgen:CLKGEN0|CK15611i}] 


#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

derive_clock_uncertainty


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************

#set_clock_groups -asynchronous -group [get_clocks { *|pll|pll_inst|altera_pll_i|general[*].gpll~PLL_OUTPUT_COUNTER|divclk}] -group [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -group [get_clocks { }] 

#**************************************************************
# Set False Path
#**************************************************************

set_false_path -from [get_ports {KEY*}] 
set_false_path -from [get_ports {BTN_*}] 
set_false_path -to [get_ports {LED_*}]
set_false_path -to [get_ports {VGA_*}]
set_false_path -to [get_ports {AUDIO_SPDIF}]
set_false_path -to [get_ports {AUDIO_L}]
set_false_path -to [get_ports {AUDIO_R}]


#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

