# Copyright (C) 2017  Intel Corporation. All rights reserved.
# Your use of Intel Corporation's design tools, logic functions 
# and other software and tools, and its AMPP partner logic 
# functions, and any output files from any of the foregoing 
# (including device programming or simulation files), and any 
# associated documentation or information are expressly subject 
# to the terms and conditions of the Intel Program License 
# Subscription Agreement, the Intel Quartus Prime License Agreement,
# the Intel MegaCore Function License Agreement, or other 
# applicable license agreement, including, without limitation, 
# that your use is for the sole purpose of programming logic 
# devices manufactured by Intel and sold by Intel or its 
# authorized distributors.  Please refer to the applicable 
# agreement for further details.

# Quartus Prime: Generate Tcl File for Project
# File: sharpmz.tcl
# Generated on: Wed Jun 20 13:50:16 2018

# Load Quartus Prime Tcl Project package
package require ::quartus::project

set need_to_close_project 0
set make_assignments 1

# Check that the right project is open
if {[is_project_open]} {
	if {[string compare $quartus(project) "sharpmz"]} {
		puts "Project sharpmz is not open"
		set make_assignments 0
	}
} else {
	# Only open if not already open
	if {[project_exists sharpmz]} {
		project_open -revision sharpmz-lite sharpmz
	} else {
		project_new -revision sharpmz-lite sharpmz
	}
	set need_to_close_project 1
}

# Make assignments
if {$make_assignments} {
	set_global_assignment -name VERILOG_MACRO "LITE=1"
	set_global_assignment -name FAMILY "Cyclone V"
	set_global_assignment -name DEVICE 5CSEBA6U23I7
	set_global_assignment -name TOP_LEVEL_ENTITY sys_top
	set_global_assignment -name ORIGINAL_QUARTUS_VERSION 16.1.2
	set_global_assignment -name LAST_QUARTUS_VERSION "17.0.2 Lite Edition"
	set_global_assignment -name PROJECT_CREATION_TIME_DATE "01:53:30  APRIL 20, 2017"
	set_global_assignment -name DEVICE_FILTER_PACKAGE UFBGA
	set_global_assignment -name DEVICE_FILTER_PIN_COUNT 672
	set_global_assignment -name DEVICE_FILTER_SPEED_GRADE 7
	set_global_assignment -name GENERATE_RBF_FILE ON
	set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
	set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
	set_global_assignment -name SAVE_DISK_SPACE OFF
	set_global_assignment -name SMART_RECOMPILE ON
	set_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id Top
	set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id Top
	set_global_assignment -name PARTITION_COLOR 16764057 -section_id Top
	set_global_assignment -name MIN_CORE_JUNCTION_TEMP "-40"
	set_global_assignment -name MAX_CORE_JUNCTION_TEMP 100
	set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"
	set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"
	set_global_assignment -name TIMEQUEST_MULTICORNER_ANALYSIS OFF
	set_global_assignment -name OPTIMIZE_POWER_DURING_FITTING OFF
	set_global_assignment -name FINAL_PLACEMENT_OPTIMIZATION ALWAYS
	set_global_assignment -name FITTER_EFFORT "STANDARD FIT"
	set_global_assignment -name OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT"
	set_global_assignment -name SEED 1
	set_global_assignment -name PRE_FLOW_SCRIPT_FILE "quartus_sh:sys/build_id.tcl"
	set_global_assignment -name CDF_FILE jtag.cdf
	set_global_assignment -name QIP_FILE sys/sys.qip
	set_global_assignment -name VHDL_FILE jtag_uart_0.vhd
	set_global_assignment -name SYSTEMVERILOG_FILE sharpmz.sv
	set_global_assignment -name VHDL_FILE mz80c/T80/T80_Reg.vhd
	set_global_assignment -name VHDL_FILE mz80c/T80/T80_Pack.vhd
	set_global_assignment -name VHDL_FILE mz80c/T80/T80_MCode.vhd
	set_global_assignment -name VHDL_FILE mz80c/T80/T80_ALU.vhd
	set_global_assignment -name VHDL_FILE mz80c/T80/T80.vhd
	set_global_assignment -name VHDL_FILE mz80c/T80/T80s.vhd
	set_global_assignment -name VHDL_FILE mz80c/cmt.vhd
	set_global_assignment -name VHDL_FILE mz80c/counter0.vhd
	set_global_assignment -name VHDL_FILE mz80c/counter1.vhd
	set_global_assignment -name VHDL_FILE mz80c/counter2.vhd
	set_global_assignment -name VHDL_FILE mz80c/dpram64k.vhd
	set_global_assignment -name VHDL_FILE mz80c/dpram.vhd
	set_global_assignment -name VHDL_FILE mz80c/i8253.vhd
	set_global_assignment -name VHDL_FILE mz80c/i8255.vhd
	set_global_assignment -name VHDL_FILE mz80c/keymatrix.vhd
	set_global_assignment -name VHDL_FILE mz80c/ls367.vhd
	set_global_assignment -name VHDL_FILE mz80c/mctrl.vhd
	set_global_assignment -name VHDL_FILE mz80c/sharpmz.vhd
	set_global_assignment -name VHDL_FILE mz80c/pcg.vhd
	set_global_assignment -name VERILOG_FILE mz80c/pll_mz80c.v
	set_global_assignment -name VERILOG_FILE mz80c/pll_mz80c_1.v
	set_global_assignment -name VHDL_FILE mz80c/ps2kb.vhd
	set_global_assignment -name VHDL_FILE mz80c/ScanConv.vhd
	set_global_assignment -name VHDL_FILE mz80c/dprom.vhd
	set_global_assignment -name VHDL_FILE mz80c/videoout.vhd
	set_global_assignment -name VHDL_FILE mz80c/clk_div.vhd
	set_global_assignment -name VHDL_FILE mz80c/clkgen.vhd
	set_global_assignment -name VHDL_FILE mz80c/mrom.vhd
	set_global_assignment -name VHDL_FILE mz80c/ram1k.vhd
	set_global_assignment -name QIP_FILE mz80c/linebuf.qip
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ADC_CONVST
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ADC_SCK
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ADC_SDI
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ADC_SDO
	set_location_assignment PIN_U9 -to ADC_CONVST
	set_location_assignment PIN_V10 -to ADC_SCK
	set_location_assignment PIN_AC4 -to ADC_SDI
	set_location_assignment PIN_AD4 -to ADC_SDO
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[3]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[4]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[5]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[6]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[7]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[8]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[9]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[10]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[11]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[12]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[13]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[14]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[15]
	set_location_assignment PIN_AG9 -to ARDUINO_IO[3]
	set_location_assignment PIN_U14 -to ARDUINO_IO[4]
	set_location_assignment PIN_U13 -to ARDUINO_IO[5]
	set_location_assignment PIN_AG8 -to ARDUINO_IO[6]
	set_location_assignment PIN_AH8 -to ARDUINO_IO[7]
	set_location_assignment PIN_AF17 -to ARDUINO_IO[8]
	set_location_assignment PIN_AE15 -to ARDUINO_IO[9]
	set_location_assignment PIN_AF15 -to ARDUINO_IO[10]
	set_location_assignment PIN_AG16 -to ARDUINO_IO[11]
	set_location_assignment PIN_AH11 -to ARDUINO_IO[12]
	set_location_assignment PIN_AH12 -to ARDUINO_IO[13]
	set_location_assignment PIN_AH9 -to ARDUINO_IO[14]
	set_location_assignment PIN_AG11 -to ARDUINO_IO[15]
	set_location_assignment PIN_AF25 -to SDIO_DAT[0]
	set_location_assignment PIN_AF23 -to SDIO_DAT[1]
	set_location_assignment PIN_AD26 -to SDIO_DAT[2]
	set_location_assignment PIN_AF28 -to SDIO_DAT[3]
	set_location_assignment PIN_AF27 -to SDIO_CMD
	set_location_assignment PIN_AH26 -to SDIO_CLK
	set_location_assignment PIN_AH7 -to SDIO_CD
	set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to SDIO_*
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDIO_*
	set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SDIO_DAT[*]
	set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SDIO_CMD
	set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SDIO_CD
	set_location_assignment PIN_AE17 -to VGA_R[0]
	set_location_assignment PIN_AE20 -to VGA_R[1]
	set_location_assignment PIN_AF20 -to VGA_R[2]
	set_location_assignment PIN_AH18 -to VGA_R[3]
	set_location_assignment PIN_AH19 -to VGA_R[4]
	set_location_assignment PIN_AF21 -to VGA_R[5]
	set_location_assignment PIN_AE19 -to VGA_G[0]
	set_location_assignment PIN_AG15 -to VGA_G[1]
	set_location_assignment PIN_AF18 -to VGA_G[2]
	set_location_assignment PIN_AG18 -to VGA_G[3]
	set_location_assignment PIN_AG19 -to VGA_G[4]
	set_location_assignment PIN_AG20 -to VGA_G[5]
	set_location_assignment PIN_AG21 -to VGA_B[0]
	set_location_assignment PIN_AA20 -to VGA_B[1]
	set_location_assignment PIN_AE22 -to VGA_B[2]
	set_location_assignment PIN_AF22 -to VGA_B[3]
	set_location_assignment PIN_AH23 -to VGA_B[4]
	set_location_assignment PIN_AH21 -to VGA_B[5]
	set_location_assignment PIN_AH22 -to VGA_HS
	set_location_assignment PIN_AG24 -to VGA_VS
	set_location_assignment PIN_AH27 -to VGA_EN
	set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to VGA_EN
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_*
	set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to VGA_*
	set_location_assignment PIN_AC24 -to AUDIO_L
	set_location_assignment PIN_AE25 -to AUDIO_R
	set_location_assignment PIN_AG26 -to AUDIO_SPDIF
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to AUDIO_*
	set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to AUDIO_*
	set_location_assignment PIN_Y11 -to SDRAM_A[0]
	set_location_assignment PIN_AA26 -to SDRAM_A[1]
	set_location_assignment PIN_AA13 -to SDRAM_A[2]
	set_location_assignment PIN_AA11 -to SDRAM_A[3]
	set_location_assignment PIN_W11 -to SDRAM_A[4]
	set_location_assignment PIN_Y19 -to SDRAM_A[5]
	set_location_assignment PIN_AB23 -to SDRAM_A[6]
	set_location_assignment PIN_AC23 -to SDRAM_A[7]
	set_location_assignment PIN_AC22 -to SDRAM_A[8]
	set_location_assignment PIN_C12 -to SDRAM_A[9]
	set_location_assignment PIN_AB26 -to SDRAM_A[10]
	set_location_assignment PIN_AD17 -to SDRAM_A[11]
	set_location_assignment PIN_D12 -to SDRAM_A[12]
	set_location_assignment PIN_Y17 -to SDRAM_BA[0]
	set_location_assignment PIN_AB25 -to SDRAM_BA[1]
	set_location_assignment PIN_E8 -to SDRAM_DQ[0]
	set_location_assignment PIN_V12 -to SDRAM_DQ[1]
	set_location_assignment PIN_D11 -to SDRAM_DQ[2]
	set_location_assignment PIN_W12 -to SDRAM_DQ[3]
	set_location_assignment PIN_AH13 -to SDRAM_DQ[4]
	set_location_assignment PIN_D8 -to SDRAM_DQ[5]
	set_location_assignment PIN_AH14 -to SDRAM_DQ[6]
	set_location_assignment PIN_AF7 -to SDRAM_DQ[7]
	set_location_assignment PIN_AE24 -to SDRAM_DQ[8]
	set_location_assignment PIN_AD23 -to SDRAM_DQ[9]
	set_location_assignment PIN_AE6 -to SDRAM_DQ[10]
	set_location_assignment PIN_AE23 -to SDRAM_DQ[11]
	set_location_assignment PIN_AG14 -to SDRAM_DQ[12]
	set_location_assignment PIN_AD5 -to SDRAM_DQ[13]
	set_location_assignment PIN_AF4 -to SDRAM_DQ[14]
	set_location_assignment PIN_AH3 -to SDRAM_DQ[15]
	set_location_assignment PIN_AG13 -to SDRAM_DQML
	set_location_assignment PIN_AF13 -to SDRAM_DQMH
	set_location_assignment PIN_AD20 -to SDRAM_CLK
	set_location_assignment PIN_AG10 -to SDRAM_CKE
	set_location_assignment PIN_AA19 -to SDRAM_nWE
	set_location_assignment PIN_AA18 -to SDRAM_nCAS
	set_location_assignment PIN_Y18 -to SDRAM_nCS
	set_location_assignment PIN_W14 -to SDRAM_nRAS
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_*
	set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to SDRAM_*
	set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A*
	set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_BA*
	set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[*]
	set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQM*
	set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_n*
	set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to SDRAM_DQ[*]
	set_instance_assignment -name ALLOW_SYNCH_CTRL_USAGE OFF -to *|SDRAM_*
	set_location_assignment PIN_Y15 -to LED_USER
	set_location_assignment PIN_AA15 -to LED_HDD
	set_location_assignment PIN_AG28 -to LED_POWER
	set_location_assignment PIN_AH24 -to BTN_USER
	set_location_assignment PIN_AG25 -to BTN_OSD
	set_location_assignment PIN_AG23 -to BTN_RESET
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED_*
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to BTN_*
	set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to BTN_*
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to FPGA_CLK1_50
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to FPGA_CLK2_50
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to FPGA_CLK3_50
	set_location_assignment PIN_V11 -to FPGA_CLK1_50
	set_location_assignment PIN_Y13 -to FPGA_CLK2_50
	set_location_assignment PIN_E11 -to FPGA_CLK3_50
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_I2C_SCL
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_I2C_SDA
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_I2S
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_LRCLK
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_MCLK
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_SCLK
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_CLK
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_DE
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[0]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[1]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[2]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[3]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[4]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[5]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[6]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[7]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[8]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[9]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[10]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[11]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[12]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[13]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[14]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[15]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[16]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[17]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[18]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[19]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[20]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[21]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[22]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_D[23]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_HS
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_INT
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HDMI_TX_VS
	set_location_assignment PIN_U10 -to HDMI_I2C_SCL
	set_location_assignment PIN_AA4 -to HDMI_I2C_SDA
	set_location_assignment PIN_T13 -to HDMI_I2S
	set_location_assignment PIN_T11 -to HDMI_LRCLK
	set_location_assignment PIN_U11 -to HDMI_MCLK
	set_location_assignment PIN_T12 -to HDMI_SCLK
	set_location_assignment PIN_AG5 -to HDMI_TX_CLK
	set_location_assignment PIN_AD19 -to HDMI_TX_DE
	set_location_assignment PIN_AD12 -to HDMI_TX_D[0]
	set_location_assignment PIN_AE12 -to HDMI_TX_D[1]
	set_location_assignment PIN_W8 -to HDMI_TX_D[2]
	set_location_assignment PIN_Y8 -to HDMI_TX_D[3]
	set_location_assignment PIN_AD11 -to HDMI_TX_D[4]
	set_location_assignment PIN_AD10 -to HDMI_TX_D[5]
	set_location_assignment PIN_AE11 -to HDMI_TX_D[6]
	set_location_assignment PIN_Y5 -to HDMI_TX_D[7]
	set_location_assignment PIN_AF10 -to HDMI_TX_D[8]
	set_location_assignment PIN_Y4 -to HDMI_TX_D[9]
	set_location_assignment PIN_AE9 -to HDMI_TX_D[10]
	set_location_assignment PIN_AB4 -to HDMI_TX_D[11]
	set_location_assignment PIN_AE7 -to HDMI_TX_D[12]
	set_location_assignment PIN_AF6 -to HDMI_TX_D[13]
	set_location_assignment PIN_AF8 -to HDMI_TX_D[14]
	set_location_assignment PIN_AF5 -to HDMI_TX_D[15]
	set_location_assignment PIN_AE4 -to HDMI_TX_D[16]
	set_location_assignment PIN_AH2 -to HDMI_TX_D[17]
	set_location_assignment PIN_AH4 -to HDMI_TX_D[18]
	set_location_assignment PIN_AH5 -to HDMI_TX_D[19]
	set_location_assignment PIN_AH6 -to HDMI_TX_D[20]
	set_location_assignment PIN_AG6 -to HDMI_TX_D[21]
	set_location_assignment PIN_AF9 -to HDMI_TX_D[22]
	set_location_assignment PIN_AE8 -to HDMI_TX_D[23]
	set_location_assignment PIN_T8 -to HDMI_TX_HS
	set_location_assignment PIN_AF11 -to HDMI_TX_INT
	set_location_assignment PIN_V13 -to HDMI_TX_VS
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY[0]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY[1]
	set_location_assignment PIN_AH17 -to KEY[0]
	set_location_assignment PIN_AH16 -to KEY[1]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[0]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[1]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[2]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[3]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[4]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[5]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[6]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[7]
	set_location_assignment PIN_W15 -to LED[0]
	set_location_assignment PIN_AA24 -to LED[1]
	set_location_assignment PIN_V16 -to LED[2]
	set_location_assignment PIN_V15 -to LED[3]
	set_location_assignment PIN_AF26 -to LED[4]
	set_location_assignment PIN_AE26 -to LED[5]
	set_location_assignment PIN_Y16 -to LED[6]
	set_location_assignment PIN_AA23 -to LED[7]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[0]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[1]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[2]
	set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[3]
	set_location_assignment PIN_Y24 -to SW[0]
	set_location_assignment PIN_W24 -to SW[1]
	set_location_assignment PIN_W21 -to SW[2]
	set_location_assignment PIN_W20 -to SW[3]
	set_instance_assignment -name PARTITION_HIERARCHY root_partition -to | -section_id Top

	# Including default assignments
	set_global_assignment -name REVISION_TYPE BASE -family "Cyclone V"
	set_global_assignment -name TIMEQUEST_REPORT_WORST_CASE_TIMING_PATHS OFF -family "Cyclone V"
	set_global_assignment -name TIMEQUEST_CCPP_TRADEOFF_TOLERANCE 0 -family "Cyclone V"
	set_global_assignment -name TDC_CCPP_TRADEOFF_TOLERANCE 30 -family "Cyclone V"
	set_global_assignment -name TIMEQUEST_DO_CCPP_REMOVAL ON -family "Cyclone V"
	set_global_assignment -name TIMEQUEST_SPECTRA_Q OFF -family "Cyclone V"
	set_global_assignment -name SYNTH_TIMING_DRIVEN_SYNTHESIS ON -family "Cyclone V"
	set_global_assignment -name SYNCHRONIZATION_REGISTER_CHAIN_LENGTH 3 -family "Cyclone V"
	set_global_assignment -name SYNTH_RESOURCE_AWARE_INFERENCE_FOR_BLOCK_RAM ON -family "Cyclone V"
	set_global_assignment -name STRATIXV_CONFIGURATION_SCHEME "PASSIVE SERIAL" -family "Cyclone V"
	set_global_assignment -name OPTIMIZE_HOLD_TIMING "ALL PATHS" -family "Cyclone V"
	set_global_assignment -name OPTIMIZE_MULTI_CORNER_TIMING ON -family "Cyclone V"
	set_global_assignment -name AUTO_DELAY_CHAINS ON -family "Cyclone V"
	set_global_assignment -name CRC_ERROR_OPEN_DRAIN ON -family "Cyclone V"
	set_global_assignment -name ACTIVE_SERIAL_CLOCK FREQ_100MHZ -family "Cyclone V"
	set_global_assignment -name ADVANCED_PHYSICAL_OPTIMIZATION ON -family "Cyclone V"
	set_global_assignment -name ENABLE_OCT_DONE OFF -family "Cyclone V"

	# Commit assignments
	export_assignments

	# Close project
	if {$need_to_close_project} {
		project_close
	}
}
