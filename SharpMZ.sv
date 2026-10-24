//=======================================================================================================
//
// Name:            SharpMZ.sv
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
	"F2,MZF,Load Direct to RAM;",
	"S0,MZTMZF,Tape Image;",
	"S1,DSKD88D77,Floppy Drive A;",
	"S2,DSKD88D77,Floppy Drive B;",
	"S3,QDFMZQMZTMZF,Quick Disk;",
	"-;",
	"P1,Machine;",
	"P1O[38:35],Model,MZ-80K,MZ-80C,MZ-80A,MZ-1200,MZ-80B,MZ-2000,MZ-700,MZ-800,MZ-1500;",
	"P1O[6:4],CPU Speed,Normal,2x,4x,8x,16x,Fastest;",
	"P1O[30],MZ-80B/2000 Boot Reset,Off,On;",
	"P1O[32],MZ-800 Mode,MZ-700,MZ-800;",
	"P1O[56],Region,Europe,Japan;",
	"P1O[39],MZ-1X03 Joysticks,Off,On;",
	"P1O[51],Keyboard Layout,PC,Sharp;",
	"-;",
	"P2,Tape;",
	"P2T[31],Rewind Tape Image;",
	"P2O[25:24],Tape Buttons,Auto,Off,Play,Record;",
	"P2O[23:21],Fast Tape,Fastest,Off,2x,4x,8x,16x;",
	"P2O[27:26],Sharp ASCII Name,Off,On Save,On Load,Both;",
	"P2O[54:53],Tape Sound,Off,Mix,Only;",
	"P2O[49],Load Direct Start,Program,Reset Only;",
	"P2O[52],Tape Image Start,Tape,Direct;",
	"P2O[59],Auto Load Tape,Off,On;",
	"P2O[55],Tape Messages,On,Off;",
	"P2O[57],Tape Details,Off,On;",
	"P2R[58],Show Tape Details;",
	"-;",
	"P3,Display;",
	"P3O[8:7],Display Type,Default,Mono 80x25,Colour 40x25,Colour 80x25;",
			"P3O[18],VRAM Wait,On,Off;",
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
	// System ROM and CGROM are remembered: Main loads the last one chosen at every core start (also boot.rom).
	"P4FC3,ROMBIN,Load System ROM;",
	"P4F4,ROMBIN,Load System RAM;",
	"P4FC6,ROMBIN,Load CGROM;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	// The joystick entries go after every menu entry: placed before Reset they broke the OSD's Reset and
	// Reset and close OSD (testers: "you press reset and nothing happens").
	"J1,Fire 1,Fire 2;",
	"jn,A,B;",
	"v,6;",
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

wire        hps_ioctl_wait;

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
	.ioctl_wait(hps_ioctl_wait),                     // Only while a byte of a tape download waits for DDR3 (sharpmz_top).

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

/////////////////  MACHINE  /////////////////////
// Everything between hps_io and video_mixer (configuration from the OSD bits, downloads, resets, tape, disks,
// printer, border, tape messages) is rtl/sharpmz_top.sv, which the Verilator simulation uses as well.

wire reset = RESET | ~pll_locked;
wire       ce_pix_emu;
wire [7:0] R_osd, G_osd, B_osd;
wire       hsync_emu, vsync_emu, hblank_brd, vblank_brd;
wire       led_disk;

sharpmz_top sharpmz_top
(
	.clk_sys(clk_sys),
	.reset(reset),

	.status(status),
	.buttons(buttons),
	.ps2_key(ps2_key),
	.joy0(joystick_0[5:0]),
	.joy1(joystick_1[5:0]),
	.uart_speed(uart_speed),

	.hps_ioctl_download(hps_ioctl_download),
	.hps_ioctl_upload(hps_ioctl_upload),
	.hps_ioctl_index(hps_ioctl_index),
	.hps_ioctl_wr(hps_ioctl_wr),
	.hps_ioctl_rd(hps_ioctl_rd),
	.hps_ioctl_addr(hps_ioctl_addr),
	.hps_ioctl_dout(hps_ioctl_dout),
	.hps_ioctl_din(hps_ioctl_din),
	.hps_ioctl_wait(hps_ioctl_wait),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE),

	.ce_pix(ce_pix_emu),
	.vga_r(R_osd), .vga_g(G_osd), .vga_b(B_osd),
	.vga_hs(hsync_emu), .vga_vs(vsync_emu), .vga_hb(hblank_brd), .vga_vb(vblank_brd),
	.audio_l(AUDIO_L),
	.audio_r(AUDIO_R),

	.uart_txd(UART_TXD),
	.led_user(LED_USER),
	.led_disk(led_disk)
);
assign DDRAM_CLK = clk_sys;
assign AUDIO_S   = 0;
assign AUDIO_MIX = 0;
assign LED_DISK  = {1'b0, led_disk};
assign CLK_VIDEO = clk_sys;

// Native 15 kHz video, or doubled to 31 kHz for VGA monitors (MiSTer.ini forced_scandoubler, or the OSD
// Scandoubler Fx: HQ2x or CRT scanlines). The pixel enable is at most 17.7344 MHz, a quarter of clk_sys.
wire [2:0] scale = status[46:44];
wire [2:0] sl    = scale ? scale - 1'd1 : 3'd0;
assign VGA_SL = sl[1:0];

video_mixer #(.LINE_LENGTH(1024), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(ce_pix_emu),
	.scandoubler(scale || forced_scandoubler),
	.hq2x(scale == 3'd1),
	.gamma_bus(gamma_bus),
	.R(R_osd), .G(G_osd), .B(B_osd),
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
