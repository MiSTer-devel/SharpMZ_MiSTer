## SDC file "sharpmz.sdc"

#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

#create_clock -name {altera_reserved_tck} -period 100.000 -waveform { 0.000 50.000 } [get_ports {altera_reserved_tck}]
#create_clock -name {FPGA_CLK1_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK1_50}]
#create_clock -name {FPGA_CLK2_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK2_50}]
#create_clock -name {MCLK} -period 10.000 -waveform { 0.000 5.000 } [get_ports {SDRAM_CLK}]
#create_clock -name {SDCLK} -period 100.000 -waveform { 0.000 50.000 } [get_ports {SDIO_CLK}]
#create_clock -name {VMCLK} -period 10.000 -waveform { 0.000 5.000 } 

#create_clock -name {CK32Mi} -period 31.250 -waveform { 0.000 15.625 }
#create_generated_clock -source [get_pins -compatibility_mode {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] \
#                       -name HDMI_CLK [get_ports HDMI_TX_CLK]

#create_generated_clock -source [get_pins -compatibility_mode {emu:emu|sharpmz:sharp_mz|clkgen:CLKGEN0|CK32Mi}] -name CK32Mi
#create_generated_clock -source {emu:emu|sharpmz:sharp_mz|clkgen:CLKGEN0|CK8Mi} -name CK8Mi
#create_generated_clock -source [get_pins -compatibility_mode {emu:emu|sharpmz:sharp_mz|clkgen:CLKGEN0|pll:PLLMAIN|pll_0002:pll_inst|altera_pll:altera_pll_i|outclk_wire[0]}] -name {CK32Mi} -period 31.250 
#-waveform { 0.000 15.625 }




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
#set_output_delay -add_delay  -clock [get_clocks {altera_reserved_tck}]  0.000 [get_ports {altera_reserved_tdo}]


#**************************************************************
# Set Clock Groups
#**************************************************************

#set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
#set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
#set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
#set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
#set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
#set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
#set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
#set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 


#**************************************************************
# Set False Path
#**************************************************************

#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|jupdate}] -to [get_registers {*|alt_jtag_atlantic:*|jupdate1*}]
#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|rdata[*]}] -to [get_registers {*|alt_jtag_atlantic*|td_shift[*]}]
#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|read_req}] 
#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|read_write}] -to [get_registers {*|alt_jtag_atlantic:*|read_write1*}]
#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|rvalid}] -to [get_registers {*|alt_jtag_atlantic*|td_shift[*]}]
#set_false_path -from [get_registers {*|t_dav}] -to [get_registers {*|alt_jtag_atlantic:*|td_shift[0]*}]
#set_false_path -from [get_registers {*|t_dav}] -to [get_registers {*|alt_jtag_atlantic:*|write_stalled*}]
#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|user_saw_rvalid}] -to [get_registers {*|alt_jtag_atlantic:*|rvalid0*}]
#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|wdata[*]}] -to [get_registers *]
#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|write_stalled}] -to [get_registers {*|alt_jtag_atlantic:*|t_ena*}]
#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|write_stalled}] -to [get_registers {*|alt_jtag_atlantic:*|t_pause*}]
#set_false_path -from [get_registers {*|alt_jtag_atlantic:*|write_valid}] 
#set_false_path -to [get_keepers {*altera_std_synchronizer:*|din_s1}]
#set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_break:the_cpu_0_nios2_oci_break|break_readreg*}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr*}]
#set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_debug:the_cpu_0_nios2_oci_debug|*resetlatch}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr[33]}]
#set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_debug:the_cpu_0_nios2_oci_debug|monitor_ready}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr[0]}]
#set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_debug:the_cpu_0_nios2_oci_debug|monitor_error}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr[34]}]
#set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_ocimem:the_cpu_0_nios2_ocimem|*MonDReg*}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr*}]
#set_false_path -from [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_tck:the_cpu_0_jtag_debug_module_tck|*sr*}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_sysclk:the_cpu_0_jtag_debug_module_sysclk|*jdo*}]
#set_false_path -from [get_keepers {sld_hub:*|irf_reg*}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_jtag_debug_module_wrapper:the_cpu_0_jtag_debug_module_wrapper|cpu_0_jtag_debug_module_sysclk:the_cpu_0_jtag_debug_module_sysclk|ir*}]
#set_false_path -from [get_keepers {sld_hub:*|sld_shadow_jsm:shadow_jsm|state[1]}] -to [get_keepers {*cpu_0:*|cpu_0_nios2_oci:the_cpu_0_nios2_oci|cpu_0_nios2_oci_debug:the_cpu_0_nios2_oci_debug|monitor_go}]
#set_false_path -from [get_pins -nocase -compatibility_mode {*the*clock*|slave_writedata_d1*|*}] -to [get_registers *]
#set_false_path -from [get_pins -nocase -compatibility_mode {*the*clock*|slave_nativeaddress_d1*|*}] -to [get_registers *]
#set_false_path -from [get_pins -nocase -compatibility_mode {*the*clock*|slave_readdata_p1*}] -to [get_registers *]
#set_false_path -from [get_keepers -nocase {*the*clock*|slave_readdata_p1*}] -to [get_registers *]


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


#**************************************************************
# Active MiSTer framework migration constraints
#**************************************************************

# The modern stock sys tree expects the core clock to come from the usual
# top-level "pll" instance. SharpMZ keeps its original PLLs inside clkgen, so
# keep the framework domains decoupled from the legacy core domains here.
set sharpmz_core_clocks [get_clocks -nowarn {
    *|CLKGEN0|PLLMAIN*|altera_pll_i|*|divclk
}]

set framework_clocks [get_clocks -nowarn {
    FPGA_CLK1_50
    FPGA_CLK2_50
    FPGA_CLK3_50
    *|h2f_user0_clk
    spi_sck
    hdmi_sck
    pll_hdmi|pll_hdmi_inst|altera_pll_i|*|divclk
    pll_audio|pll_audio_inst|altera_pll_i|*|divclk
}]

if {[llength $sharpmz_core_clocks] && [llength $framework_clocks]} {
    set_false_path -from $sharpmz_core_clocks -to $framework_clocks
    set_false_path -from $framework_clocks -to $sharpmz_core_clocks
}

# The old clkgen block derives the core master clock, then samples/muxes a set
# of auxiliary PLL outputs to make legacy enables and peripheral clocks.
set sharpmz_master_clock [get_clocks -nowarn {
    *|CLKGEN0|PLLMAIN02|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk
}]

set sharpmz_aux_clocks [get_clocks -nowarn {
    *|CLKGEN0|PLLMAIN01|altera_pll_i|*|divclk
    *|CLKGEN0|PLLMAIN02|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk
    *|CLKGEN0|PLLMAIN02|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk
    *|CLKGEN0|PLLMAIN02|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk
    *|CLKGEN0|PLLMAIN02|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk
    *|CLKGEN0|PLLMAIN03|altera_pll_i|*|divclk
}]

if {[llength $sharpmz_master_clock] && [llength $sharpmz_aux_clocks]} {
    set_false_path -from $sharpmz_master_clock -to $sharpmz_aux_clocks
    set_false_path -from $sharpmz_aux_clocks -to $sharpmz_master_clock
}

# clkgen intentionally samples selectable generated clocks as data to create
# clock-enable pulses in the 56.75 MHz master domain.
set clkgen_edge_regs [get_registers -nowarn {
    *|CLKGEN0|CPUEDGE*
    *|CLKGEN0|VIDEOEDGE*
    *|CLKGEN0|LEDSEDGE*
    *|CLKGEN0|PEREDGE*
}]

if {[llength $clkgen_edge_regs]} {
    set_false_path -to $clkgen_edge_regs
}

# These are legacy clock outputs selected or divided inside clkgen and used as
# data/control sources elsewhere. They are not one-cycle datapaths into the
# 56.75 MHz master clock domain.
set clkgen_muxed_clock_regs [get_registers -nowarn {
    *|CLKGEN0|CKSOUNDi
    *|CLKGEN0|CKVIDEOi
    *|CLKGEN0|CKRTCi
}]

if {[llength $clkgen_muxed_clock_regs]} {
    set_false_path -to $clkgen_muxed_clock_regs
}

# OSD-driven clock/debug mode fields can change at human/UI speed and feed the
# legacy clock generator's muxing. Do not make TimeQuest close those as fixed
# synchronous datapaths.
set clkgen_mode_regs [get_registers -nowarn {
    *|CTRL0|CONFIG*
    *|CTRL0|DEBUG*
}]

set clkgen_regs [get_registers -nowarn {*|CLKGEN0|*}]

if {[llength $clkgen_mode_regs] && [llength $clkgen_regs]} {
    set_false_path -from $clkgen_mode_regs -to $clkgen_regs
}

# Framework reset requests are consumed by the old VHDL as asynchronous resets.
set framework_reset_regs [get_registers -nowarn {
    reset_req
    sysmem|init_reset_n
}]

if {[llength $framework_reset_regs]} {
    set_false_path -from $framework_reset_regs
}
