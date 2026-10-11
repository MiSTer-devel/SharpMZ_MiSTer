//=======================================================================================================
//
// Name:            sharpmz.sv
// Created:         June 2018
// Author(s):       Philip Smart
// Description:     Sharp MZ series compatible logic.
//
//                  MiSTer top level for the emulator (rtl/sharpmz.vhd): OSD, configuration and downloads.
//                  The sys/ directory is expected to be the stock Template_MiSTer sys drop-in.
//
// Copyright:       (C) 2018 Sorgelig
//                  (C) 2018 Philip Smart <philip.smart@net2net.org>
//
// History:         June 2018 - Initial creation.
//
//=======================================================================================================
// This source file is free software: you can redistribute it and-or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//=======================================================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

`ifdef MISTER_DUAL_SDRAM
assign {SDRAM2_DQ, SDRAM2_A, SDRAM2_BA, SDRAM2_CLK, SDRAM2_nWE, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nCS} = 'Z;
`endif

`ifdef MISTER_FB
assign FB_EN = 0;
assign FB_FORMAT = 0;
assign FB_WIDTH = 0;
assign FB_HEIGHT = 0;
assign FB_BASE = 0;
assign FB_STRIDE = 0;
assign FB_FORCE_BLANK = 0;
`ifdef MISTER_FB_PALETTE
assign FB_PAL_CLK = 0;
assign FB_PAL_ADDR = 0;
assign FB_PAL_DOUT = 0;
assign FB_PAL_WR = 0;
`endif
`endif

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

`include "build_id.v"

localparam CONF_STR =
{
	"SharpMZ;UART9600:19200:38400:4800:2400:1200;",
	"-;",
	// Tape and disk entries stay on the top level: MGL files can only load F/S entries that are
	// not on a sub-page.
	"F1,MZF,Load Tape to CMT;",
	"F2,MZF,Load Direct to RAM;",
	"S0,MZTMZF,Tape Image;",
	"S1,DSKD88D77,Floppy Drive A;",
	"S2,DSKD88D77,Floppy Drive B;",
	"S3,QDFMZQ,Quick Disk;",
	"-;",
	"P1,Machine;",
	"P1O[38:35],Model,MZ80A,MZ80K,MZ80C,MZ1200,MZ700,MZ80B,MZ2000,MZ800,MZ1500;",
	"P1O[6:4],CPU Speed,Default,+1,+2,+3,+4,+5,+6,+7;",
	"P1O[30],Boot Reset,Off,On;",
	"P1O[32],MZ-800 Mode,MZ-700,MZ-800;",
	"P1O[39],MZ-1X03 Joysticks,Off,On;",
	"P1O[51],Keyboard Layout,PC,Sharp;",
	"-;",
	"P2,Tape;",
	"P2T[31],Rewind Tape Image;",
	"P2O[25:24],Tape Buttons,Auto,Off,Play,Record;",
	"P2O[23:21],Fast Tape,Default,Off,2x,4x,8x,16x,32x,Default;",
	"P2O[27:26],Sharp ASCII Name,Off,On Save,On Load,Both;",
	"P2O[20],Audio Source,Sound,Tape;",
	"P2O[41],Tape Sound,Off,On;",
	"P2O[49],Load Direct,Start Program,Reset Only;",
	"P2O[52],Tape Image Start,Tape,Direct;",
	"-;",
	"P3,Display;",
	"P3O[8:7],Display Type,Default,Mono 80x25,Colour 40x25,Colour 80x25;",
	"P3O[16],Video,On,Off;",
	"P3O[17],Graphics,On,Off;",
	"P3O[18],VRAM Wait,Off,On;",
	"P3O[43],MZ-800 Border,Off,On;",
	"P3O[46:44],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"P5,Floppy;",
	"P5O[34:33],Floppy Interface,Auto,On,Off;",
	"P5O[40],MZ-800 RAM Disk,Off,64 KB;",
	"P5O[42],Floppy CRC Errors,Ignore,Report;",
	"P5O[48],Drive B Unit,2nd drive,3rd (CP/M 4.1 HD);",
	"-;",
	"P6,Printer;",
	"P6O[47],Printer,None,UART (mister_printerd);",
	"P6O[50],Printer Charset,Sharp,ASCII;",
	"P6-;",
	"P6-,Set UART connection to Printer;",
	"P6-,in the MiSTer UART menu;",
	"-;",
	"P4,ROM and RAM;",
	"P4O[28],User ROM,Off,On;",
	"P4O[29],FDC ROM,Off,On;",
	"P4F3,ROMBIN,Load System ROM,0x000000;",
	"P4F4,ROMBIN,Load System RAM,0x100000;",
	"P4F5,ROMBIN,Load Keymap,0x200000;",
	"P4F6,ROMBIN,Load CGROM,0x500000;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	// The joystick entries go after every menu entry: placed before Reset they broke the OSD's Reset and
	// Reset and close OSD (testers: "you press reset and nothing happens").
	"J1,Fire 1,Fire 2;",
	"jn,A,B;",
	"v,5;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

// 70.9376 MHz = 4 x the 17.7344 MHz MZ-700 crystal. rtl/clkgen.vhd derives all
// machine clock enables from it (CLK_HZ must match).
wire clk_sys;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

/////////////////  HPS  ///////////////////////////

wire forced_scandoubler;
wire [21:0] gamma_bus;
wire [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire [31:0] joystick_0, joystick_1;

wire        hps_ioctl_download;
wire        hps_ioctl_upload;
wire [15:0] hps_ioctl_index;
wire        hps_ioctl_wr;
wire        hps_ioctl_rd;
wire [26:0] hps_ioctl_addr;
wire  [7:0] hps_ioctl_dout;
wire  [7:0] hps_ioctl_din;
wire [31:0] hps_ioctl_file_ext;

// Image slots: S0 tape image, S1/S2 floppy drives A/B.
wire  [3:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba[4];
wire  [3:0] sd_rd;
wire  [3:0] sd_wr;
wire  [3:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[4];
wire        sd_buff_wr;

wire        tape_active;
wire        tape_ram_load;                          // tape_image: Tape Image Start: Direct, first record going to RAM
wire        warm_reset_user;                        // the resets that also reset the tape engine (below)
reg         tape_ram_load_d = 0;
wire        ds_bus_active, ds_bus_wr, ds_inj_go;   // Load Direct start (direct_start, below)
wire [24:0] ds_bus_addr;
wire  [7:0] ds_bus_dout, ds_inj_data;
wire        cpu_m1_n, cpu_mreq_n, cpu_rd_n;
wire        tape_data_region, tape_rd, tape_b_busy;   // tape data buffer in DDR3 (tape_ddr, below)
wire  [7:0] tape_b_dout;

wire [31:0] uart_speed;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(4)) hps_io
(
	.clk_sys(clk_sys),
	.uart_speed(uart_speed),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.buttons(buttons),
	.status(status),
	.status_in(128'd0),
	.status_set(1'b0),
	.status_menumask(16'd0),
	.forced_scandoubler(forced_scandoubler),
	.video_rotated(1'b0),
	.new_vmode(1'b0),

	.ps2_key(ps2_key),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_kbd_led_status(3'd0),
	.ps2_kbd_led_use(3'd0),

	.ioctl_download(hps_ioctl_download),
	.ioctl_upload(hps_ioctl_upload),
	.ioctl_index(hps_ioctl_index),
	.ioctl_wr(hps_ioctl_wr),
	.ioctl_rd(hps_ioctl_rd),
	.ioctl_addr(hps_ioctl_addr),
	.ioctl_dout(hps_ioctl_dout),
	.ioctl_din(hps_ioctl_din),
	.ioctl_file_ext(hps_ioctl_file_ext),
	.ioctl_upload_req(1'b0),
	.ioctl_upload_index(8'd0),
	.ioctl_wait(hps_ioctl_download & tape_b_busy),   // Only while a byte of a tape download waits for DDR3.

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_blk_cnt('{6'd0, 6'd0, 6'd0, 6'd0}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.info_req(1'b0),
	.info(8'd0)
);

/////////////////  CONFIG ADAPTER  ////////////////

function automatic [2:0] mz_model_code(input [3:0] menu_sel);
	begin
		case(menu_sel)
			4'd0: mz_model_code = 3'd3; // MZ80A
			4'd1: mz_model_code = 3'd0; // MZ80K
			4'd2: mz_model_code = 3'd1; // MZ80C
			4'd3: mz_model_code = 3'd2; // MZ1200
			4'd4: mz_model_code = 3'd4; // MZ700
			4'd5: mz_model_code = 3'd6; // MZ80B
			4'd6: mz_model_code = 3'd7; // MZ2000
			4'd8: mz_model_code = 3'd4; // MZ1500: an MZ-700 plus cfg_mz1500
			default: mz_model_code = 3'd5; // MZ800
		endcase
	end
endfunction

function automatic [2:0] mz_display_type(input [1:0] menu_sel, input [2:0] model);
	begin
		case(menu_sel)
			2'd0: begin
				case(model)
					3'd4,
					3'd5: mz_display_type = 3'd2; // MZ700/MZ800 default to colour 40x25.
					3'd6,
					3'd7: mz_display_type = 3'd1; // MZ80B/MZ2000 default to mono 80x25.
					default: mz_display_type = 3'd0; // MZ80K/C/1200/A default to mono 40x25.
				endcase
			end
			2'd1: mz_display_type = 3'd1; // Mono 80x25.
			2'd2: mz_display_type = 3'd2; // Colour 40x25.
			default: mz_display_type = 3'd3; // Colour 80x25.
		endcase
	end
endfunction

function automatic [1:0] mz_tape_buttons(input [1:0] menu_sel);
	begin
		case(menu_sel)
			2'd0: mz_tape_buttons = 2'b11; // Auto.
			2'd1: mz_tape_buttons = 2'b00; // Off.
			2'd2: mz_tape_buttons = 2'b01; // Play.
			default: mz_tape_buttons = 2'b10; // Record.
		endcase
	end
endfunction

function automatic [2:0] mz_fast_tape(input [2:0] menu_sel);
	begin
		case(menu_sel)
			3'd0: mz_fast_tape = 3'b110; // Core default.
			3'd1: mz_fast_tape = 3'b000; // Off/original speed.
			3'd2: mz_fast_tape = 3'b001; // 2x.
			3'd3: mz_fast_tape = 3'b010; // 4x.
			3'd4: mz_fast_tape = 3'b011; // 8x.
			3'd5: mz_fast_tape = 3'b100; // 16x.
			3'd6: mz_fast_tape = 3'b101; // 32x; every model is capped at clk_sys/2 (about 35 MHz).
			default: mz_fast_tape = 3'b110; // Core default.
		endcase
	end
endfunction

wire [2:0] cfg_model = mz_model_code(status[38:35]);
wire       cfg_mz1500 = (status[38:35] == 4'd8);
wire [2:0] cfg_display = mz_display_type(status[8:7], cfg_model);
wire [1:0] cfg_tape_buttons = mz_tape_buttons(status[25:24]);
wire [2:0] cfg_fast_tape = mz_fast_tape(status[23:21]);
wire [7:0] cfg_userrom = (status[28] | cfg_mz1500) ? (8'd1 << cfg_model) : 8'd0;  // MZ-1500: E800-EFFF is always ROM
wire       fdc_present;
wire [7:0] cfg_fdcrom  = (status[29] | cfg_mz1500 | (fdc_present & cfg_model == 3'b100)) ? (8'd1 << cfg_model) : 8'd0;  // MZ-700: the MZ-1E05 ROM comes with the interface (the MZ-1500 has its own F000 ROM)

wire [7:0] cfg_reg0_model   = {5'd0, cfg_model};
wire [7:0] cfg_reg1_display = {1'b0, status[18], status[17], status[16], 1'b0, cfg_display};  // PCG is software controlled (E010-E012).
wire [7:0] cfg_reg2_display = 8'd3;                    // Native timing (the video is native-only).
wire [7:0] cfg_reg3_display = {4'd0, cfg_mz1500, status[32], 2'b00};   // 3: MZ-1500. 2: MZ-800 rear mode switch (0 = MZ-700, as mz800emu's default; 1 = MZ-800).
wire [7:0] cfg_reg4_cpu     = {status[30], 4'd0, status[6:4]};
wire [7:0] cfg_reg5_audio   = {7'd0, status[20]};
wire [7:0] cfg_reg6_cmt     = {1'b0, status[27], status[26], cfg_tape_buttons, cfg_fast_tape};
wire [7:0] cfg_reg8_userrom = cfg_userrom;
wire [7:0] cfg_reg9_fdcrom  = cfg_fdcrom;

/////////////////  DOWNLOAD ROUTING  //////////////

localparam [5:0] FILE_TAPE_CMT    = 6'd1;
localparam [5:0] FILE_TAPE_DIRECT = 6'd2;
localparam [24:0] IOCTL_SYSRAM_BASE = 25'h0100000;

reg hps_ioctl_download_d = 0;
reg [5:0] active_file_slot = 0;
reg [15:0] mzf_size = 0;
reg [15:0] mzf_load_addr = 0;
reg [7:0] direct_load_reset_ctr = 0;

always @(posedge clk_sys) begin
	hps_ioctl_download_d <= hps_ioctl_download;

	if(!hps_ioctl_download_d && hps_ioctl_download) begin
		active_file_slot <= hps_ioctl_index[5:0];
		mzf_size <= 0;
		mzf_load_addr <= 0;
	end

	tape_ram_load_d <= tape_ram_load;
	if((hps_ioctl_download_d && !hps_ioctl_download && active_file_slot == FILE_TAPE_DIRECT) ||
	   (tape_ram_load_d && !tape_ram_load)) begin
		direct_load_reset_ctr <= 8'd64;
	end
	else if(direct_load_reset_ctr != 0) begin
		direct_load_reset_ctr <= direct_load_reset_ctr - 1'd1;
	end

	if(hps_ioctl_download && hps_ioctl_wr && active_file_slot == FILE_TAPE_DIRECT) begin
		case(hps_ioctl_addr)
			27'd18: mzf_size[7:0] <= hps_ioctl_dout;
			27'd19: mzf_size[15:8] <= hps_ioctl_dout;
			27'd20: mzf_load_addr[7:0] <= hps_ioctl_dout;
			27'd21: mzf_load_addr[15:8] <= hps_ioctl_dout;
			default: begin end
		endcase
	end
end

wire        direct_load_active = hps_ioctl_download && active_file_slot == FILE_TAPE_DIRECT;
wire [26:0] mzf_direct_end = 27'd128 + {11'd0, mzf_size};
wire        mzf_direct_wr_valid = active_file_slot != FILE_TAPE_DIRECT ||
                                  hps_ioctl_addr < 27'd128 ||
                                  mzf_size == 16'd0 ||
                                  hps_ioctl_addr < mzf_direct_end;

function automatic [24:0] mz_ioctl_addr_map(
	input [5:0] slot,
	input [26:0] addr,
	input [15:0] load_addr
);
	begin
		case(slot)
			FILE_TAPE_CMT:
				mz_ioctl_addr_map = (addr < 27'd128) ? (25'h0400000 + addr[24:0])
				                                      : (25'h0410000 + (addr[24:0] - 25'd128));
			FILE_TAPE_DIRECT:
				mz_ioctl_addr_map = (addr < 27'd128) ? (IOCTL_SYSRAM_BASE + 25'h0010F0 + addr[24:0])
				                                      : (IOCTL_SYSRAM_BASE + {9'd0, load_addr} + (addr[24:0] - 25'd128));
			default:
				mz_ioctl_addr_map = addr[24:0];
		endcase
	end
endfunction

wire [24:0] hps_ioctl_addr_mapped = mz_ioctl_addr_map(active_file_slot, hps_ioctl_addr, mzf_load_addr);

wire [31:0] mz_ioctl_din;

assign hps_ioctl_din = mz_ioctl_din[7:0];

/////////////////  TAPE IMAGE  ////////////////////

wire [13:0] cmt_status;
wire  [7:0] cmt_ctrl;                               // CMT_BUS_IN: bit 0 is the machine's write (record) bit.
wire [24:0] tape_addr;
wire        tape_wr;
wire  [7:0] tape_dout;
wire        tape_mounted, tape_full;
wire  [7:0] tape_record;

tape_image tape_image
(
	.clk(clk_sys),
	.reset(reset | warm_reset_user),          // a machine reset clears the CMT, so the engine reloads its record

	.img_mounted(img_mounted[0]),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba[0]),
	.sd_rd(sd_rd[0]),
	.sd_wr(sd_wr[0]),
	.sd_ack(sd_ack[0]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din[0]),
	.sd_buff_wr(sd_buff_wr),

	.rewind(status[31]),
	.direct_first(status[52] & (cfg_model[2:1] != 2'b11)),   // Tape Image Start: Direct (not the MZ-80B/2000)
	.ram_load(tape_ram_load),
	.host_busy(hps_ioctl_download | ds_bus_active),
	.cmt_status(cmt_status),

	.active(tape_active),
	.bus_addr(tape_addr),
	.bus_wr(tape_wr),
	.bus_dout(tape_dout),
	.bus_din(tape_data_region ? tape_b_dout : mz_ioctl_din[7:0]),
	.bus_busy(tape_b_busy),
	.bus_rd(tape_rd),

	.mounted(tape_mounted),
	.tape_full(tape_full),
	.record_no(tape_record)
);

// Core download bus: the tape engine, an OSD download, or parked on an unused address. The CMT clears
// its record-ready flag whenever the bus points at its buffers, so it must not idle there.
wire        mz_ioctl_wr   = hps_ioctl_download ? (hps_ioctl_wr && mzf_direct_wr_valid) : ds_bus_active ? ds_bus_wr : tape_active & tape_wr;
wire [24:0] mz_ioctl_addr = hps_ioctl_download ? hps_ioctl_addr_mapped : ds_bus_active ? ds_bus_addr : tape_active ? tape_addr : 25'h1000000;
wire  [7:0] mz_ioctl_dout = hps_ioctl_download ? hps_ioctl_dout : ds_bus_active ? ds_bus_dout : tape_dout;

// Load Direct starts the program: after the machine has booted, the bytes the load put in 10F0-11FF are written
// back and the CPU is fed DI, the bank switches the program needs, LD SP,10F0 and JP exec (rtl/direct_start.sv).
wire vblank_emu;                                    // core video vblank (declared here: direct_start uses it)
direct_start #(.CLK_HZ(70937600)) direct_start
(
	.clk(clk_sys),
	.reset(reset),
	.enable(~status[49] & (cfg_model[2:1] != 2'b11)),   // not the MZ-80B / MZ-2000
	.is_mz800(cfg_model == 3'd5),
	.has_e0(cfg_model[2]),
	.vblank(vblank_emu),
	.dl_active(direct_load_active | tape_ram_load),
	.dl_wr(mz_ioctl_wr),
	.dl_addr(mz_ioctl_addr),
	.dl_data(mz_ioctl_dout),
	.bus_active(ds_bus_active),
	.bus_wr(ds_bus_wr),
	.bus_addr(ds_bus_addr),
	.bus_dout(ds_bus_dout),
	.m1_n(cpu_m1_n),
	.mreq_n(cpu_mreq_n),
	.rd_n(cpu_rd_n),
	.inj_go(ds_inj_go),
	.inj_data(ds_inj_data)
);

// The CMT's tape data buffer (64 KB) is in DDR3 (rtl/tape_ddr.sv): the CMT plays and records through port A,
// downloads and tape_image through port B (the data region of the core bus, 410000-41FFFF).
assign      tape_data_region = (mz_ioctl_addr[24:16] == 9'h041);
wire [15:0] tapedata_addr;
wire  [7:0] tapedata_wdata, tapedata_rdata;
wire        tapedata_we, tapedata_ready;

tape_ddr tape_ddr
(
	.clk(clk_sys),
	.reset(reset),
	.a_addr(tapedata_addr),
	.a_we(tapedata_we),
	.a_din(tapedata_wdata),
	.a_dout(tapedata_rdata),
	.a_ready(tapedata_ready),
	.b_addr(mz_ioctl_addr[15:0]),
	.b_we(mz_ioctl_wr & tape_data_region),
	.b_rd(~hps_ioctl_download & tape_active & tape_rd & tape_data_region),
	.b_din(mz_ioctl_dout),
	.b_dout(tape_b_dout),
	.b_busy(tape_b_busy),
	.DDRAM_CLK(DDRAM_CLK),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE)
);

/////////////////  RESET  /////////////////////////

wire reset = RESET | ~pll_locked;
// OSD Reset (status[0]) is a pulse of a few microseconds (Main sets the bit and clears it at once); stretch any reset
// request to about 1 ms of clk_sys, so the core's asynchronously loaded reset one-shot (mctrl.vhd) gets a clean edge.
reg  [16:0] reset_stretch = 0;
always @(posedge clk_sys) begin
	if (status[0] | buttons[1]) reset_stretch <= 17'h1FFFF;
	else if (reset_stretch != 0) reset_stretch <= reset_stretch - 1'd1;
end
assign warm_reset_user = status[0] | buttons[1] | (reset_stretch != 0) | direct_load_active | (direct_load_reset_ctr != 0);
wire warm_reset = warm_reset_user | tape_ram_load;     // the tape image putting its first record in RAM (Tape Image Start)

////////////////  Machine  ////////////////////////

wire audio_l_emu;
wire audio_r_emu;
// 1-bit sound (8253 or tape signal, per the Audio Source option) at half scale; the framework's
// DC blocker centres it. Full scale was harsh and sat at a large DC offset.
wire [13:0] audio_psg;                              // MZ-800 PSG mix; MZ-1500 left PSG (0 on other models).
wire [13:0] audio_psg_r;                            // MZ-1500 right PSG; the MZ-800 PSG otherwise.
// The beeper (8253 counter 0) is as loud as one PSG channel on the machines with a PSG, as mz800emu mixes them
// (each source at the same gain); on the others it is the only source and uses the full range.
wire        has_psg = (cfg_model == 3'b101) | cfg_mz1500;
wire [15:0] beep_l  = has_psg ? {3'b000, audio_l_emu, 12'd0} : {1'b0, audio_l_emu, 14'd0};
wire [15:0] beep_r  = has_psg ? {3'b000, audio_r_emu, 12'd0} : {1'b0, audio_r_emu, 14'd0};
// Tape Sound: the tape signal (playback, cmt_status[6]; recording, cmt_ctrl[0]) mixed in quietly while the tape
// moves (cmt_status[4]), like a deck's monitor speaker; Audio Source = Tape plays it instead of the sound.
wire        tape_bit = cmt_status[4] & (cmt_status[6] | cmt_ctrl[0]);
wire [15:0] tape_snd = (status[41] & tape_bit) ? 16'h0800 : 16'd0;

// Printer (OSD Printer: UART): the MZ-700 / MZ-800 / MZ-1500 printer port, sent out of the MiSTer UART for the
// printer daemon (rtl/mz_printer.sv).
wire        prn_rda, prn_stb, prn_txd;
wire  [7:0] prn_data;
mz_printer #(.CLK_HZ(70937600)) mz_printer
(
	.clk(clk_sys),
	.reset(reset),
	.enable(status[47]),
	.ascii(status[50]),
	.rdp(prn_stb),
	.data(prn_data),
	.rda(prn_rda),
	.uart_speed(uart_speed),
	.txd(prn_txd),
	.count()
);
assign UART_TXD = status[47] ? prn_txd : 1'b1;
assign AUDIO_L = beep_l + {2'b00, audio_psg} + tape_snd;
assign AUDIO_R = beep_r + {2'b00, audio_psg_r} + tape_snd;
assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

wire clk_video_in;
wire [7:0] R_emu;
wire [7:0] G_emu;
wire [7:0] B_emu;
wire hblank_emu;
wire hsync_emu;
wire vsync_emu;
wire [3:0] mz800_bcol;
wire [7:0] main_leds;

// Floppy disk interface (MZ-700/MZ-800), drives A/B on image slots S1/S2.
wire [7:0] ext_io_addr, ext_io_dout, ext_io_din;
wire       ext_io_rd, ext_io_wr, ext_io_oe, ext_int_n, ext_ce_cpu;
wire       fdd_busy;
wire [31:0] fdc_lba[2];
wire [7:0]  fdc_buff_din[2];

mz_fdc mz_fdc
(
	.clk_sys(clk_sys),
	.reset(reset),
	.ce_cpu(ext_ce_cpu),
	.model_ok(cfg_model[2]),                    // MZ-700, MZ-800, MZ-80B, MZ-2000
	.mode(status[34:33]),
	.crc_report(status[42]),
	.b_unit2(status[48]),

	.io_addr(ext_io_addr),
	.io_rd(ext_io_rd),
	.io_wr(ext_io_wr),
	.io_dout(ext_io_dout),
	.io_din(fdc_io_din),
	.io_oe(fdc_io_oe),
	.int_n(ext_int_n),

	.img_mounted(img_mounted[2:1]),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(fdc_lba),
	.sd_rd(sd_rd[2:1]),
	.sd_wr(sd_wr[2:1]),
	.sd_ack(sd_ack[2:1]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(fdc_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.busy(fdd_busy),
	.present(fdc_present)
);
// Quick Disk (MZ-1500 built in; MZ-800 MZ-1F11 when an image is mounted) on image slot S3.
wire [7:0] fdc_io_din, qd_io_din;
wire       fdc_io_oe, qd_io_oe, qd_busy;
reg        qd_mounted = 0;
always @(posedge clk_sys) if (img_mounted[3]) qd_mounted <= |img_size;
assign ext_io_oe  = fdc_io_oe | qd_io_oe;
assign ext_io_din = fdc_io_oe ? fdc_io_din : qd_io_din;

mz_qdisk mz_qdisk
(
	.clk_sys(clk_sys),
	.reset(reset),
	.enable(cfg_mz1500 | (cfg_model == 3'b101 & qd_mounted)),

	.io_addr(ext_io_addr),
	.io_rd(ext_io_rd),
	.io_wr(ext_io_wr),
	.io_dout(ext_io_dout),
	.io_din(qd_io_din),
	.io_oe(qd_io_oe),

	.img_mounted(img_mounted[3]),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba[3]),
	.sd_rd(sd_rd[3]),
	.sd_wr(sd_wr[3]),
	.sd_ack(sd_ack[3]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din[3]),
	.sd_buff_wr(sd_buff_wr),

	.busy(qd_busy)
);

assign sd_lba[1] = fdc_lba[0];
assign sd_lba[2] = fdc_lba[1];
assign sd_buff_din[1] = fdc_buff_din[0];
assign sd_buff_din[2] = fdc_buff_din[1];

sharpmz sharp_mz
(
	// System clock; the core runs everything on it with clock enables.
	.CLKMASTER(clk_sys),
	.CLKSYS(),
	.CLKVID(clk_video_in),
	.CLKIOP(),

	.COLD_RESET(reset),
	.WARM_RESET(warm_reset),

	.MAIN_LEDS(main_leds),

	.PS2_KEY(ps2_key),
	.JOY0(joystick_0[5:0]),         // MZ-800: ports F0/F1; MZ-700/1500: MZ-1X03 on E008 when enabled.
	.JOY1(joystick_1[5:0]),
	.JOY_1X03(status[39]),
	.KEY_SHARP(status[51]),
	.RAMDISK_EN(status[40]),
	.PRN_EN(status[47]),
	.PRN_RDA(prn_rda),
	.PRN_DATA(prn_data),
	.PRN_STB(prn_stb),
	.TAPEDATA_ADDR(tapedata_addr),
	.TAPEDATA_DOUT(tapedata_wdata),
	.TAPEDATA_WE(tapedata_we),
	.TAPEDATA_DIN(tapedata_rdata),
	.TAPEDATA_READY(tapedata_ready),
	.INJ_GO(ds_inj_go),
	.INJ_DATA(ds_inj_data),
	.CPU_M1_n(cpu_m1_n),
	.CPU_MREQ_n(cpu_mreq_n),
	.CPU_RD_n(cpu_rd_n),

	.VGA_HB_O(hblank_emu),
	.VGA_VB_O(vblank_emu),
	.VGA_HS_O(hsync_emu),
	.VGA_VS_O(vsync_emu),
	.BCOL_O(mz800_bcol),
	.VGA_R_O(R_emu),
	.VGA_G_O(G_emu),
	.VGA_B_O(B_emu),

	.AUDIO_L_O(audio_l_emu),
	.AUDIO_R_O(audio_r_emu),
	.AUDIO_PSG_O(audio_psg),
	.AUDIO_PSG_R_O(audio_psg_r),

	.CMT_STATUS(cmt_status),
	.CMT_CTRL(cmt_ctrl),
	.EXT_IO_ADDR(ext_io_addr),
	.EXT_IO_RD(ext_io_rd),
	.EXT_IO_WR(ext_io_wr),
	.EXT_IO_DOUT(ext_io_dout),
	.EXT_IO_DIN(ext_io_din),
	.EXT_IO_OE(ext_io_oe),
	.EXT_INT_n(ext_int_n),
	.EXT_CE_CPU(ext_ce_cpu),

	// Machine configuration from the OSD.
	.CFG_MODEL(cfg_reg0_model),
	.CFG_DISPLAY(cfg_reg1_display),
	.CFG_DISPLAY2(cfg_reg2_display),
	.CFG_DISPLAY3(cfg_reg3_display),
	.CFG_CPU(cfg_reg4_cpu),
	.CFG_AUDIO(cfg_reg5_audio),
	.CFG_CMT(cfg_reg6_cmt),
	.CFG_USERROM(cfg_reg8_userrom),
	.CFG_FDCROM(cfg_reg9_fdcrom),

	// ROM, keymap and tape downloads.
	.IOCTL_DOWNLOAD(hps_ioctl_download),
	.IOCTL_UPLOAD(hps_ioctl_upload),
	.IOCTL_CLK(clk_sys),
	.IOCTL_WR(mz_ioctl_wr),
	.IOCTL_RD(hps_ioctl_rd),
	.IOCTL_ADDR(mz_ioctl_addr),
	.IOCTL_DOUT({24'd0, mz_ioctl_dout}),
	.IOCTL_DIN(mz_ioctl_din)
);

assign LED_USER = hps_ioctl_download;
assign LED_DISK = {1'b0, tape_active | cmt_status[4] | fdd_busy | qd_busy};    // Tape image, CMT, floppy or Quick Disk activity.

assign CLK_VIDEO = clk_sys;

// MZ-800 border colour around the picture (OSD Display > MZ-800 Border); otherwise the picture as it is.
wire [7:0] R_brd, G_brd, B_brd;
wire       hblank_brd, vblank_brd;
mz800_border mz800_border
(
	.clk(clk_sys),
	.ce_pix(clk_video_in),
	.enable(status[43] & (cfg_model == 3'b101)),
	.hblank(hblank_emu),
	.vblank(vblank_emu),
	.bcol(mz800_bcol),
	.r_in(R_emu), .g_in(G_emu), .b_in(B_emu),
	.r_out(R_brd), .g_out(G_brd), .b_out(B_brd),
	.hblank_out(hblank_brd),
	.vblank_out(vblank_brd)
);

// Native 15 kHz video, or doubled to 31 kHz for VGA monitors (MiSTer.ini forced_scandoubler, or the OSD
// Scandoubler Fx: HQ2x or CRT scanlines). The pixel enable is at most 17.7344 MHz, a quarter of clk_sys.
wire [2:0] scale = status[46:44];
wire [2:0] sl    = scale ? scale - 1'd1 : 3'd0;
assign VGA_SL = sl[1:0];

video_mixer #(.LINE_LENGTH(1024), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(clk_video_in),
	.scandoubler(scale || forced_scandoubler),
	.hq2x(scale == 3'd1),
	.gamma_bus(gamma_bus),
	.R(R_brd), .G(G_brd), .B(B_brd),
	.HSync(hsync_emu), .VSync(vsync_emu),
	.HBlank(hblank_brd), .VBlank(vblank_brd),
	.HDMI_FREEZE(1'b0),
	.freeze_sync(),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_VS(VGA_VS), .VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

endmodule
