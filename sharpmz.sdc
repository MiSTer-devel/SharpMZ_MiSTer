## Generated SDC file "sharpmz.sdc"

## Copyright (C) 1991-2011 Altera Corporation
## Your use of Altera Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Altera Program License 
## Subscription Agreement, Altera MegaCore Function License 
## Agreement, or other applicable license agreement, including, 
## without limitation, that your use is for the sole purpose of 
## programming logic devices manufactured by Altera and sold by 
## Altera or its authorized distributors.  Please refer to the 
## applicable agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus II"
## VERSION "Version 11.0 Build 208 07/03/2011 Service Pack 1 SJ Web Edition"

## DATE    "Mon Jul 16 23:49:03 2012"

##
## DEVICE  "EP3C16F484C6"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {altera_reserved_tck} -period 100.000 -waveform { 0.000 50.000 } [get_ports {altera_reserved_tck}]
create_clock -name {FPGA_CLK1_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK1_50}]
create_clock -name {FPGA_CLK2_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK2_50}]
#create_clock -name {MCLK} -period 10.000 -waveform { 0.000 5.000 } [get_ports {SDRAM_CLK}]
#create_clock -name {SDCLK} -period 100.000 -waveform { 0.000 50.000 } [get_ports {SDIO_CLK}]
#create_clock -name {VMCLK} -period 10.000 -waveform { 0.000 5.000 } 


#**************************************************************
# Create Generated Clock
#**************************************************************



#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************



#**************************************************************
# Set Input Delay
#**************************************************************

#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[0]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[0]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[1]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[1]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[2]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[2]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[3]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[3]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[4]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[4]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[5]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[5]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[6]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[6]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[7]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[7]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[8]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[8]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[9]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[9]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[10]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[10]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[11]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[11]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[12]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[12]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[13]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[13]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[14]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[14]}]
#set_input_delay -add_delay -max -clock [get_clocks {VMCLK}]  6.000 [get_ports {SDRAM_DQ[15]}]
#set_input_delay -add_delay -min -clock [get_clocks {VMCLK}]  0.000 [get_ports {SDRAM_DQ[15]}]


#**************************************************************
# Set Output Delay
#**************************************************************

#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[0]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[1]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[2]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[3]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[4]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[5]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[6]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[7]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[8]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[9]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_A[10]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_nCAS}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_nCS}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[0]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[1]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[2]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[3]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[4]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[5]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[6]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[7]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[8]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[9]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[10]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[11]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[12]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[13]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[14]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQ[15]}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQML}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_nRAS}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_DQMH}]
#set_output_delay -add_delay  -clock [get_clocks {MCLK}]  0.000 [get_ports {SDRAM_nWE}]
#set_output_delay -add_delay  -clock [get_clocks {SDCLK}]  0.000 [get_ports {SDIO_CMD}]
#set_output_delay -add_delay  -clock [get_clocks {SDCLK}]  0.000 [get_ports {SDIO_DAT[3]}]
set_output_delay -add_delay  -clock [get_clocks {altera_reserved_tck}]  0.000 [get_ports {altera_reserved_tdo}]


#**************************************************************
# Set Clock Groups
#**************************************************************

set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 


#**************************************************************
# Set False Path
#**************************************************************

set_false_path -from [get_registers {*|alt_jtag_atlantic:*|jupdate}] -to [get_registers {*|alt_jtag_atlantic:*|jupdate1*}]
set_false_path -from [get_registers {*|alt_jtag_atlantic:*|rdata[*]}] -to [get_registers {*|alt_jtag_atlantic*|td_shift[*]}]
set_false_path -from [get_registers {*|alt_jtag_atlantic:*|read_req}] 
set_false_path -from [get_registers {*|alt_jtag_atlantic:*|read_write}] -to [get_registers {*|alt_jtag_atlantic:*|read_write1*}]
set_false_path -from [get_registers {*|alt_jtag_atlantic:*|rvalid}] -to [get_registers {*|alt_jtag_atlantic*|td_shift[*]}]
set_false_path -from [get_registers {*|t_dav}] -to [get_registers {*|alt_jtag_atlantic:*|td_shift[0]*}]
set_false_path -from [get_registers {*|t_dav}] -to [get_registers {*|alt_jtag_atlantic:*|write_stalled*}]
set_false_path -from [get_registers {*|alt_jtag_atlantic:*|user_saw_rvalid}] -to [get_registers {*|alt_jtag_atlantic:*|rvalid0*}]
set_false_path -from [get_registers {*|alt_jtag_atlantic:*|wdata[*]}] -to [get_registers *]
set_false_path -from [get_registers {*|alt_jtag_atlantic:*|write_stalled}] -to [get_registers {*|alt_jtag_atlantic:*|t_ena*}]
set_false_path -from [get_registers {*|alt_jtag_atlantic:*|write_stalled}] -to [get_registers {*|alt_jtag_atlantic:*|t_pause*}]
set_false_path -from [get_registers {*|alt_jtag_atlantic:*|write_valid}] 
set_false_path -to [get_keepers {*altera_std_synchronizer:*|din_s1}]
set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_break:the_cpu_0_nios2_oci_break|break_readreg*}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr*}]
set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_debug:the_cpu_0_nios2_oci_debug|*resetlatch}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr[33]}]
set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_debug:the_cpu_0_nios2_oci_debug|monitor_ready}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr[0]}]
set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_debug:the_cpu_0_nios2_oci_debug|monitor_error}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr[34]}]
set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_ocimem:the_cpu_0_nios2_ocimem|*MonDReg*}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr*}]
set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr*}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_sysclk:the_cpu_0_jtag_debug_module_sysclk|*jdo*}]
set_false_path -from [get_keepers {sld_hub:*|irf_reg*}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_sysclk:the_cpu_0_jtag_debug_module_sysclk|ir*}]
set_false_path -from [get_keepers {sld_hub:*|sld_shadow_jsm:shadow_jsm|state[1]}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_debug:the_cpu_0_nios2_oci_debug|monitor_go}]
set_false_path -from [get_pins -nocase -compatibility_mode {*the*clock*|slave_writedata_d1*|*}] -to [get_registers *]
set_false_path -from [get_pins -nocase -compatibility_mode {*the*clock*|slave_nativeaddress_d1*|*}] -to [get_registers *]
set_false_path -from [get_pins -nocase -compatibility_mode {*the*clock*|slave_readdata_p1*}] -to [get_registers *]
set_false_path -from [get_keepers -nocase {*the*clock*|slave_readdata_p1*}] -to [get_registers *]


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

