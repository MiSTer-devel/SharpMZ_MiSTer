#============================================================================
#  SharpMZ Verilator simulation
#
#    make            # headless sim            -> ./obj_dir_headless/Vtop
#    make netlist    # VHDL -> Verilog only    -> gen/sharpmz.v
#    make test       # smoke tests (run_tests.sh)
#    make test-clkgen  # GHDL testbench for the clock enable generator
#    make test-i8254   # GHDL testbench for the 8253/8254 timer
#    make test-cmt     # GHDL testbench for the tape unit (record kept over a deck stop)
#    make fast       # the same sim at half clk_sys (35.47 MHz) -> ./obj_dir_fast/Vtop,
#                    # about twice as fast; for batch runs (run_tests.sh BIN=... shows what differs)
#    make clean
#
#  The RTL is VHDL and Verilator reads only Verilog, so every build starts by
#  running the core through "ghdl synth", which emits a Verilog netlist. Module,
#  instance and register names survive; combinational nodes become nNNNN.
#
#  dpram/dprom (Altera altsyncram wrappers) are not analysed: ghdl leaves them
#  as black boxes and rtl_v/dpram.v, rtl_v/dprom.v supply the memories. Their
#  .mif init files are converted to software/mif/<name>.mif.hex.
#
#  Requires: ghdl (5.x), verilator (5.x), python3.
#============================================================================

V      = verilator
GHDL   = ghdl
RTL    = ../rtl
GEN    = gen
# clk_sys divider for the sim build: 1 = 70.9376 MHz as the FPGA, 2 = `make fast`. Every clock enable comes
# from clkgen_pkg's CLK_SYS_HZ, so a copy of that package with the rate divided is analysed instead.
SIM_CLK_DIV = 1
WORK   = ghdl_work

GHDL_FLAGS = --std=08 -fsynopsys -fexplicit -frelaxed -Wno-hide -Wno-shared -Wno-binding \
	--workdir=$(WORK) --work=pkgs

# Analysis order: packages first, then leaves, then the assembly.
VHD_SRC = \
	$(RTL)/config_pkg.vhd \
	$(CLK_PKG) \
	$(RTL)/mctrl_pkg.vhd \
	$(RTL)/functions.vhd \
	$(RTL)/clkgen.vhd \
	$(RTL)/mctrl.vhd \
	$(RTL)/T80/T80_Pack.vhd \
	$(RTL)/T80/T80_ALU.vhd \
	$(RTL)/T80/T80_Reg.vhd \
	$(RTL)/T80/T80_MCode.vhd \
	$(RTL)/T80/T80.vhd \
	$(RTL)/T80/T80se.vhd \
	$(RTL)/i8254/i8254_counter.vhd \
	$(RTL)/i8254/i8254.vhd \
	$(RTL)/i8255/i8255.vhd \
	$(RTL)/z8420/Interrupt.vhd \
	$(RTL)/z8420/z8420.vhd \
	$(RTL)/keymatrix.vhd \
	$(RTL)/cmt.vhd \
	$(RTL)/sn76489_audio.vhd \
	$(RTL)/vc/vc_rams.vhd \
	$(RTL)/mz80c/mz800_pio.vhd \
	$(RTL)/mz80c/mz80c.vhd \
	$(RTL)/mz80b/mz80b.vhd \
	$(RTL)/vc/vc_mctrl_pkg.vhd \
	$(RTL)/vc/VideoController_pkg.vhd \
	$(RTL)/vc/VideoController.vhd \
	$(RTL)/vc/video_vc.vhd \
	$(RTL)/sharpmz.vhd

ifeq ($(SIM_CLK_DIV),1)
CLK_PKG = $(RTL)/clkgen_pkg.vhd
else
CLK_PKG = $(GEN)/clkgen_pkg.vhd
$(CLK_PKG): $(RTL)/clkgen_pkg.vhd Makefile
	@mkdir -p $(GEN)
	perl -pe 's/(CLK_SYS_HZ\s*:\s*natural\s*:=\s*)70937600/$${1}70937600 \/ $(SIM_CLK_DIV)/' $< > $@
	grep -q "70937600 / $(SIM_CLK_DIV)" $@
endif

GEN_V = $(GEN)/sharpmz.v
V_SRC = sim.v $(GEN_V) rtl_v/dpram.v rtl_v/dprom.v $(RTL)/tape_image.sv $(RTL)/mz_fdc.sv $(RTL)/mz_qdisk.sv $(RTL)/mz800_border.sv $(RTL)/mz_printer.sv $(RTL)/tape_ddr.sv $(RTL)/direct_start.sv $(RTL)/wd1793.sv $(RTL)/wd1793_mem.v

MIFS    = $(wildcard $(RTL)/software/mif/*.mif)
MIF_HEX = $(patsubst $(RTL)/software/mif/%.mif,software/mif/%.mif.hex,$(MIFS))

V_OPT = -O3 --x-assign fast --x-initial fast --noassert \
	-Wno-fatal -Wno-PINMISSING -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
	-Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME -Wno-MULTIDRIVEN -Wno-LATCH \
	-Wno-TIMESCALEMOD -Wno-COMBDLY

CXXFLAGS = -O3 -std=c++17 -DSIM_CLK_DIV=$(SIM_CLK_DIV)
HL_DIR   = obj_dir_headless
HL_EXE   = ./$(HL_DIR)/Vtop

all: headless

headless: $(HL_EXE) $(MIF_HEX)

# ---------------------------------------------------------------------------
# VHDL -> Verilog netlist
# ---------------------------------------------------------------------------
$(GEN_V): $(VHD_SRC) fix_port_aliases.py Makefile
	@mkdir -p $(GEN) $(WORK)
	$(GHDL) -a $(GHDL_FLAGS) $(VHD_SRC)
	$(GHDL) synth $(GHDL_FLAGS) --out=verilog sharpmz > $@.tmp
	$(GHDL) synth $(GHDL_FLAGS) --out=vhdl sharpmz > $(GEN)/sharpmz_netlist.vhd
	python3 fix_port_aliases.py $@.tmp $(GEN)/sharpmz_netlist.vhd
	@# VHDL names that are (System)Verilog keywords.
	perl -pi -e 's/\b(do|config)\b/$${1}_v/g' $@.tmp
	@mv $@.tmp $@

netlist: $(GEN_V)

software/mif/%.mif.hex: $(RTL)/software/mif/%.mif mif2hex.py
	@mkdir -p software/mif
	python3 mif2hex.py $< $@

# ---------------------------------------------------------------------------
# Headless: no SDL. Screenshots, frame logs and state dumps for regressions.
# ---------------------------------------------------------------------------
$(HL_EXE): $(V_SRC) sim_headless.cpp ps2_keys.h sharp_vcode.h Makefile
	$V -cc $(V_OPT) +define+SIM_CLK_DIV=$(SIM_CLK_DIV) --exe --build -j 0 --Mdir $(HL_DIR) --top-module top \
		-CFLAGS "$(CXXFLAGS)" $(V_SRC) sim_headless.cpp -o Vtop

fast:
	$(MAKE) headless SIM_CLK_DIV=2 GEN=gen_fast WORK=ghdl_work_fast HL_DIR=obj_dir_fast

test: headless
	./run_tests.sh


# ---------------------------------------------------------------------------
# GHDL unit testbenches.
# ---------------------------------------------------------------------------
test-clkgen: $(GEN_V)
	$(GHDL) -a $(GHDL_FLAGS) tests/tb_clkgen.vhd
	$(GHDL) -e $(GHDL_FLAGS) -o $(WORK)/tb_clkgen tb_clkgen
	cd $(WORK) && ./tb_clkgen --assert-level=error

# The tape unit on its own, with a behavioural dpram, in a separate GHDL library (ghdl_work_tb) so the
# netlist build never sees that dpram. CLK_SYS_HZ / 64 shortens the CMT's PLAY_READY quiet time.
TB_WORK  = ghdl_work_tb
TB_FLAGS = $(subst --workdir=$(WORK),--workdir=$(TB_WORK),$(GHDL_FLAGS))
test-cmt: tests/tb_cmt.vhd tests/dpram_beh.vhd $(RTL)/cmt.vhd
	@mkdir -p $(TB_WORK)
	perl -pe 's/(CLK_SYS_HZ\s*:\s*natural\s*:=\s*)70937600/$${1}70937600 \/ 64/' $(RTL)/clkgen_pkg.vhd > $(TB_WORK)/clkgen_pkg.vhd
	$(GHDL) -a $(TB_FLAGS) $(RTL)/config_pkg.vhd $(TB_WORK)/clkgen_pkg.vhd $(RTL)/mctrl_pkg.vhd tests/dpram_beh.vhd $(RTL)/cmt.vhd tests/tb_cmt.vhd
	$(GHDL) -e $(TB_FLAGS) -o $(TB_WORK)/tb_cmt tb_cmt
	cd $(TB_WORK) && ./tb_cmt --assert-level=error --ieee-asserts=disable

test-i8254: $(GEN_V)
	$(GHDL) -a $(GHDL_FLAGS) tests/tb_i8254.vhd
	$(GHDL) -e $(GHDL_FLAGS) -o $(WORK)/tb_i8254 tb_i8254
	cd $(WORK) && ./tb_i8254 --assert-level=error --ieee-asserts=disable-at-0

clean:
	rm -rf $(HL_DIR) $(GEN) $(WORK) $(TB_WORK) obj_dir_fast gen_fast ghdl_work_fast software out

.PHONY: all headless netlist test test-clkgen test-i8254 test-cmt clean fast
