//=======================================================================================================
//
// Name:            emu.sv
// Created:         June 2018
// Author(s):       Philip Smart
// Description:     Sharp MZ series compatible logic.
//                                                     
//                  This module is the main bridge between the emulator (sharpmz.vhd) and the MiSTer
//                  framework (hps_io.v/sys_top.v).
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
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign HDMI_FREEZE = 0;


assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

 
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

wire [1:0] ar = status[9:8];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;




wire [2:0] scale = status[4:2];

// Menu is handled in the MiSTer c++ program.
//
`include "build_id.v" 
localparam CONF_STR =
{
        "SHARP MZ SERIES;;",
        "J,Fire;",
	"V,v",`BUILD_DATE 
};

/////////////////  CLOCKS  ////////////////////////

wire clk_sys;




/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire        ioctl_download;
wire        ioctl_upload;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire        ioctl_rd;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire [15:0] ioctl_din;
wire        forced_scandoubler;

hps_io #(.STRLEN(($size(CONF_STR)>>3))) hps_io

//hps_io #(.CONF_STR(CONF_STR)) hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),

    .conf_str(CONF_STR),

    .buttons(buttons),
    .status(status),
    .forced_scandoubler(forced_scandoubler),

    .ioctl_download(ioctl_download),
    .ioctl_upload(ioctl_upload),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_rd(ioctl_rd),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_din(ioctl_din),
    .ioctl_wait(0),

    .sd_conf(0),
    .sd_ack_conf(),

    //.ps2_kbd_led_use(0),
    //.ps2_kbd_led_status(0),

    .ps2_key(ps2_key),
    .ps2_mouse(ps2_mouse)

    // unused
    //.joystick_0(),
    //.joystick_1(),
    //.new_vmode(),
    //.img_mounted(),
    //.img_readonly(),
    //.img_size(),
    //.sd_lba(),
    //.sd_rd(),
    //.sd_wr(),
    //.sd_ack(),
    //.sd_buff_addr(),
    //.sd_buff_dout(),
    //.sd_buff_din(),
    //.sd_buff_wr(),
    //.ps2_kbd_clk_out(),
    //.ps2_kbd_data_out(),
    //.ps2_kbd_clk_in(),
    //.ps2_kbd_data_in(),
    //.ps2_mouse_clk_out(),
    //.ps2_mouse_data_out(),
    //.ps2_mouse_data_in(),
    //.ps2_mouse_clk_in(),
    //.joystick_analog_0(),
    //.joystick_analog_1(),
    //.RTC(),
    //.TIMESTAMP()
);

/////////////////  RESET  /////////////////////////

//wire reset = RESET | status[0] | buttons[1] | status[6] | ioctl_download;
wire reset = RESET;
wire warm_reset = status[0] | buttons[1]; //| ioctl_download;

////////////////  Machine  ////////////////////////

wire [7:0] audio_l_emu;
wire [7:0] audio_r_emu;
assign AUDIO_L = {audio_l_emu,8'd0};
assign AUDIO_R = {audio_r_emu,8'd0};
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

bridge sharp_mz
(
        // Clocks Input to Emulator.
        .clkmaster(CLK_50M),

        // System clock.
        .clksys(clk_sys),

        // Clocks output by the emulator.
        .clkvid(clk_video_in),
        //.cepix(cepix),

        // Reset
        .cold_reset(reset),
        .warm_reset(warm_reset),

        // LED on MB
        .main_leds(LED_MB),

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

        .uart_rx(UART_RX),
        .uart_tx(UART_TX),
        .sd_sck(SD_SCK),
        .sd_mosi(SD_MOSI),
        .sd_miso(SD_MISO),
        .sd_cs(SD_CS),
        .sd_cd(SD_CD),

        // HPS Interface
        .ioctl_download(ioctl_download),                                        // HPS Downloading to FPGA.
        .ioctl_upload(ioctl_upload),                                            // HPS Uploading from FPGA.
        .ioctl_clk(clk_sys),                                                    // HPS I/O Clock.
        .ioctl_wr(ioctl_wr),                                                    // HPS Write Enable to FPGA.
        .ioctl_rd(ioctl_rd),                                                    // HPS Read Enable from FPGA.
        .ioctl_addr(ioctl_addr),                                                // HPS Address in FPGA to write into.
        .ioctl_dout(ioctl_dout),                                                // HPS Data to be written into FPGA.
        .ioctl_din(ioctl_din)                                                   // HPS Data to be read into HPS.
);

// If ce_pix is same as pixel clock, uncomment below and remove CE_PIXEL from .ce_pix_out below.
//
//assign CE_PIXEL=1;
assign CLK_VIDEO = clk_sys;
//assign CLK_VIDEO = clk_video_in;
assign CE_PIXEL  = clk_video_in;


assign VGA_R = R_emu;
assign VGA_G = G_emu;
assign VGA_B = B_emu;
assign VGA_VS = vsync_emu;
assign VGA_HS = hsync_emu;
assign VGA_DE = ~(vblank_emu | hblank_emu);

//video_mixer #(.HALF_DEPTH(0)) video_mixer
//video_mixer #(.LINE_LENGTH(320), .HALF_DEPTH(1)) video_mixer
//(
//    .clk_sys(clk_sys),
//    .ce_pix(clk_video_in),                                                      // Video pixel clock from core.
//    //.ce_pix_out(CE_PIXEL),
//
//    .scanlines({scale == 4, scale == 3, scale == 2}),
//    .scandoubler(scale || forced_scandoubler),
//    .hq2x(scale==1),
//
//    .mono(0),
//
//    // Input signals into the mixer, originating from the emulator.
//    .R(R_emu),
//    .G(G_emu),
//    .B(B_emu),
//
//    // Positive pulses.
//    .HSync(hsync_emu),
//    .VSync(vsync_emu),
//    .HBlank(hblank_emu),
//    .VBlank(vblank_emu),
//
//    .VGA_R(VGA_R),
//    .VGA_G(VGA_G),
//    .VGA_B(VGA_B),
//    .VGA_VS(VGA_VS),
//    .VGA_HS(VGA_HS),
//    .VGA_DE(VGA_DE)
//
//    // Outputs of the mixer are bound to the VGA_x signals defined in the sys_top module and passed into this module as parameters.
//    // These signals then feed the vga_osd -> vga_out modules in systop.v
//);

// Uncomment below and comment out video_mixer to pass original signal to sys_top.v. 
// To output original signal, edit sys_top.v and comment out vga_osd and vga_out, uncomment the assign statements.
//
//assign VGA_R = R_emu;
//assign VGA_G = G_emu;
//assign VGA_B = B_emu;
//assign VGA_HS = hsync_emu;
//assign VGA_VS = vsync_emu;
//assign VGA_DE = ~(vblank_emu | hblank_emu);

endmodule
