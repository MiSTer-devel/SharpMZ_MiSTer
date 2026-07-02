//=======================================================================================================
//
// Name:            sharpmz.sv
// Created:         June 2018
// Author(s):       Philip Smart
// Description:     Sharp MZ series compatible logic.
//
//                  This module bridges the emulator (sharpmz.vhd) to the modern MiSTer framework.
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
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

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

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

`include "build_id.v"

localparam CONF_STR =
{
	"SharpMZ;;",
	"-;",
	"P1,Machine;",
	"P1O[3:1],Model,MZ80A,MZ80K,MZ80C,MZ1200,MZ700,MZ80B,MZ2000,MZ800;",
	"P1O[6:4],CPU Speed,Default,+1,+2,+3,+4,+5,+6,+7;",
	"P1O[30],Boot Reset,Off,On;",
	"-;",
	"P2,Tape;",
	"P2F1,MZF,Load Tape to CMT;",
	"P2F2,MZF,Load Direct to RAM;",
	"P2O[25:24],Tape Buttons,Auto,Off,Play,Record;",
	"P2O[23:21],Fast Tape,Default,Off,2x,4x,8x,16x,32x,Default;",
	"P2O[27:26],Map Header,Off,Record,Play,Both;",
	"-;",
	"P3,Display;",
	"P3O[8:7],Display Type,Default,Mono 80x25,Colour 40x25,Colour 80x25;",
	"P3O[10:9],Video Timing,640x480@60,Native,640x480@75,640x480@85;",
	"P3O[16],Video,On,Off;",
	"P3O[17],Graphics,On,Off;",
	"P3O[18],VRAM Wait,Off,On;",
	"P3O[19],PCG,ROM,RAM;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
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
	"J,Fire;",
	"v,4;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_sys;

/////////////////  HPS  ///////////////////////////

wire forced_scandoubler;
wire [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;

wire        hps_ioctl_download;
wire        hps_ioctl_upload;
wire [15:0] hps_ioctl_index;
wire        hps_ioctl_wr;
wire        hps_ioctl_rd;
wire [26:0] hps_ioctl_addr;
wire  [7:0] hps_ioctl_dout;
wire  [7:0] hps_ioctl_din;
wire [31:0] hps_ioctl_file_ext;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.buttons(buttons),
	.status(status),
	.status_in(128'd0),
	.status_set(1'b0),
	.status_menumask(16'd0),
	.forced_scandoubler(forced_scandoubler),
	.video_rotated(1'b0),
	.new_vmode(1'b0),

	.ps2_key(ps2_key),
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
	.ioctl_wait(1'b0),

	.info_req(1'b0),
	.info(8'd0)
);

/////////////////  CONFIG ADAPTER  ////////////////

function automatic [2:0] mz_model_code(input [2:0] menu_sel);
	begin
		case(menu_sel)
			3'd0: mz_model_code = 3'd3; // MZ80A
			3'd1: mz_model_code = 3'd0; // MZ80K
			3'd2: mz_model_code = 3'd1; // MZ80C
			3'd3: mz_model_code = 3'd2; // MZ1200
			3'd4: mz_model_code = 3'd4; // MZ700
			3'd5: mz_model_code = 3'd6; // MZ80B
			3'd6: mz_model_code = 3'd7; // MZ2000
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

function automatic [1:0] mz_video_timing(input [1:0] menu_sel);
	begin
		case(menu_sel)
			2'd0: mz_video_timing = 2'b01; // 640x480@60
			2'd1: mz_video_timing = 2'b11; // Native machine timing.
			2'd2: mz_video_timing = 2'b10; // 640x480@75
			default: mz_video_timing = 2'b00; // 640x480@85
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
			3'd6: mz_fast_tape = 3'b101; // 32x where supported.
			default: mz_fast_tape = 3'b110; // Core default.
		endcase
	end
endfunction

wire [2:0] cfg_model = mz_model_code(status[3:1]);
wire [2:0] cfg_display = mz_display_type(status[8:7], cfg_model);
wire [1:0] cfg_vmode = mz_video_timing(status[10:9]);
wire [1:0] cfg_tape_buttons = mz_tape_buttons(status[25:24]);
wire [2:0] cfg_fast_tape = mz_fast_tape(status[23:21]);
wire [7:0] cfg_userrom = status[28] ? (8'd1 << cfg_model) : 8'd0;
wire [7:0] cfg_fdcrom  = status[29] ? (8'd1 << cfg_model) : 8'd0;

wire [7:0] cfg_reg0_model   = {5'd0, cfg_model};
wire [7:0] cfg_reg1_display = {status[19], status[18], status[17], status[16], 1'b0, cfg_display};
wire [7:0] cfg_reg2_display = {5'd0, cfg_vmode};
wire [7:0] cfg_reg3_display = 8'd0;
wire [7:0] cfg_reg4_cpu     = {status[30], 4'd0, status[6:4]};
wire [7:0] cfg_reg5_audio   = {7'd0, status[20]};
wire [7:0] cfg_reg6_cmt     = {1'b0, status[27], status[26], cfg_tape_buttons, cfg_fast_tape};
wire [7:0] cfg_reg8_userrom = cfg_userrom;
wire [7:0] cfg_reg9_fdcrom  = cfg_fdcrom;

wire [71:0] cfg_pack = {
	cfg_reg9_fdcrom,
	cfg_reg8_userrom,
	cfg_reg6_cmt,
	cfg_reg5_audio,
	cfg_reg4_cpu,
	cfg_reg3_display,
	cfg_reg2_display,
	cfg_reg1_display,
	cfg_reg0_model
};

reg [71:0] cfg_pack_shadow = ~72'd0;
reg [3:0] cfg_step = 0;
reg cfg_active = 0;
reg cfg_wr = 0;
reg [24:0] cfg_addr = 0;
reg [15:0] cfg_dout = 0;

wire hps_ioctl_active = hps_ioctl_download | hps_ioctl_upload | hps_ioctl_wr | hps_ioctl_rd;

always @(posedge clk_sys) begin
	cfg_wr <= 0;

	if(RESET) begin
		cfg_active <= 0;
		cfg_step <= 0;
		cfg_pack_shadow <= ~72'd0;
	end
	else if(!cfg_active && (cfg_pack != cfg_pack_shadow) && !hps_ioctl_active) begin
		cfg_active <= 1;
		cfg_step <= 0;
	end
	else if(cfg_active && !hps_ioctl_active) begin
		cfg_wr <= 1;
		case(cfg_step)
			4'd0: begin cfg_addr <= 25'h1000000; cfg_dout <= {8'd0, cfg_reg0_model};   end
			4'd1: begin cfg_addr <= 25'h1000001; cfg_dout <= {8'd0, cfg_reg1_display}; end
			4'd2: begin cfg_addr <= 25'h1000002; cfg_dout <= {8'd0, cfg_reg2_display}; end
			4'd3: begin cfg_addr <= 25'h1000003; cfg_dout <= {8'd0, cfg_reg3_display}; end
			4'd4: begin cfg_addr <= 25'h1000004; cfg_dout <= {8'd0, cfg_reg4_cpu};     end
			4'd5: begin cfg_addr <= 25'h1000005; cfg_dout <= {8'd0, cfg_reg5_audio};   end
			4'd6: begin cfg_addr <= 25'h1000006; cfg_dout <= {8'd0, cfg_reg6_cmt};     end
			4'd7: begin cfg_addr <= 25'h1000008; cfg_dout <= {8'd0, cfg_reg8_userrom}; end
			default: begin cfg_addr <= 25'h1000009; cfg_dout <= {8'd0, cfg_reg9_fdcrom}; end
		endcase

		if(cfg_step == 4'd8) begin
			cfg_active <= 0;
			cfg_pack_shadow <= cfg_pack;
		end
		else begin
			cfg_step <= cfg_step + 1'd1;
		end
	end
end

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

	if(hps_ioctl_download_d && !hps_ioctl_download && active_file_slot == FILE_TAPE_DIRECT) begin
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

wire        bridge_ioctl_wr   = cfg_wr ? 1'b1  : (hps_ioctl_wr && mzf_direct_wr_valid);
wire        bridge_ioctl_rd   = cfg_wr ? 1'b0  : hps_ioctl_rd;
wire [24:0] bridge_ioctl_addr = cfg_wr ? cfg_addr : hps_ioctl_addr_mapped;
wire [15:0] bridge_ioctl_dout = cfg_wr ? cfg_dout : {8'd0, hps_ioctl_dout};
wire [15:0] bridge_ioctl_din;

assign hps_ioctl_din = bridge_ioctl_din[7:0];

/////////////////  RESET  /////////////////////////

wire reset = RESET;
wire warm_reset = status[0] | buttons[1] | direct_load_active | (direct_load_reset_ctr != 0);

////////////////  Machine  ////////////////////////

wire audio_l_emu;
wire audio_r_emu;
assign AUDIO_L = {audio_l_emu, 15'd0};
assign AUDIO_R = {audio_r_emu, 15'd0};
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

wire clk_video_in;
wire [7:0] R_emu;
wire [7:0] G_emu;
wire [7:0] B_emu;
wire hblank_emu;
wire vblank_emu;
wire hsync_emu;
wire vsync_emu;
wire [7:0] main_leds;
wire bridge_uart_tx;
wire bridge_sd_sck;
wire bridge_sd_mosi;
wire bridge_sd_cs;
wire bridge_sd_cd;

bridge sharp_mz
(
	// Clocks Input to Emulator.
	.clkmaster(CLK_50M),

	// System clock.
	.clksys(clk_sys),

	// Clocks output by the emulator.
	.clkvid(clk_video_in),

	// Reset
	.cold_reset(reset),
	.warm_reset(warm_reset),

	// LED on MB
	.main_leds(main_leds),

	// PS2 via USB.
	.ps2_key(ps2_key),

	// VGA on IO daughter card.
	.vga_hb_o(hblank_emu),
	.vga_vb_o(vblank_emu),
	.vga_hs_o(hsync_emu),
	.vga_vs_o(vsync_emu),
	.vga_r_o(R_emu),
	.vga_g_o(G_emu),
	.vga_b_o(B_emu),

	// AUDIO on IO daughter card.
	.audio_l_o(audio_l_emu),
	.audio_r_o(audio_r_emu),

	.uart_rx(UART_RXD),
	.uart_tx(bridge_uart_tx),
	.sd_sck(bridge_sd_sck),
	.sd_mosi(bridge_sd_mosi),
	.sd_miso(SD_MISO),
	.sd_cs(bridge_sd_cs),
	.sd_cd(bridge_sd_cd),

	// HPS Interface
	.ioctl_download(hps_ioctl_download),
	.ioctl_upload(hps_ioctl_upload),
	.ioctl_clk(clk_sys),
	.ioctl_wr(bridge_ioctl_wr),
	.ioctl_rd(bridge_ioctl_rd),
	.ioctl_addr(bridge_ioctl_addr),
	.ioctl_dout(bridge_ioctl_dout),
	.ioctl_din(bridge_ioctl_din)
);

assign LED_USER = hps_ioctl_download;

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = clk_video_in;

assign VGA_R  = R_emu;
assign VGA_G  = G_emu;
assign VGA_B  = B_emu;
assign VGA_VS = vsync_emu;
assign VGA_HS = hsync_emu;
assign VGA_DE = ~(vblank_emu | hblank_emu);

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

endmodule
