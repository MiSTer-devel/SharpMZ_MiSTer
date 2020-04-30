## Generated SDC file "sharpmz-lite-pll.out.sdc"

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

## DATE    "Tue Oct 09 16:54:46 2018"

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

create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] -duty_cycle 50/1 -multiply_by 5243 -divide_by 512 -master_clock {FPGA_CLK3_50} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 2 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 16 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 64 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 256 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 4 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 32 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 128 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 8 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|refclkin}] -duty_cycle 50/1 -multiply_by 1135 -divide_by 256 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 5 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 64 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 32 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 160 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 80 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 40 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 20 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] 
create_generated_clock -name {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 10 -master_clock {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} [get_pins {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] 


#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK3_50}] -rise_to [get_clocks {FPGA_CLK3_50}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK3_50}] -rise_to [get_clocks {FPGA_CLK3_50}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK3_50}] -fall_to [get_clocks {FPGA_CLK3_50}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK3_50}] -fall_to [get_clocks {FPGA_CLK3_50}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK3_50}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK3_50}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK3_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK3_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK3_50}] -rise_to [get_clocks {FPGA_CLK3_50}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK3_50}] -rise_to [get_clocks {FPGA_CLK3_50}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK3_50}] -fall_to [get_clocks {FPGA_CLK3_50}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK3_50}] -fall_to [get_clocks {FPGA_CLK3_50}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK3_50}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK3_50}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK3_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK3_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {FPGA_CLK3_50}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {FPGA_CLK3_50}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {FPGA_CLK2_50}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {FPGA_CLK2_50}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.170  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.170  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {FPGA_CLK3_50}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {FPGA_CLK3_50}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {FPGA_CLK2_50}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {FPGA_CLK2_50}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.220  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.170  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK3_50}]  0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK3_50}]  0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.110  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK2_50}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK2_50}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK2_50}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK2_50}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.230  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.220  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.230  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.220  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK3_50}]  0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK3_50}]  0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.110  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK2_50}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK2_50}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK2_50}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK2_50}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.230  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.220  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.230  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.220  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[6].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.180  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.110  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {FPGA_CLK3_50}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {FPGA_CLK3_50}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {FPGA_CLK3_50}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {FPGA_CLK3_50}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {FPGA_CLK3_50}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {FPGA_CLK3_50}]  0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.220  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.220  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {FPGA_CLK3_50}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {FPGA_CLK3_50}]  0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.220  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.220  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.330  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.280  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[7].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.260  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.170  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -rise_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN2|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -fall_to [get_clocks {emu|sharp_mz|CLKGEN0|PLLMAIN1|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold 0.060  


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************



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

# Decouple different clock groups (to simplify routing)
#   -group [get_clocks { *|pll|pll_inst|altera_pll_i|general[*].gpll~PLL_OUTPUT_COUNTER|divclk}] \
#  -group [get_clocks { pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk VID_CLK}] \
set_clock_groups -asynchronous \
   -group [get_clocks { *|h2f_user0_clk}] \
   -group [get_clocks { FPGA_CLK1_50 FPGA_CLK2_50 FPGA_CLK3_50}]

