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
    inout  [44:0] HPS_BUS,

    //Base video clock. Usually equals to CLK_SYS.
    output        CLK_VIDEO,

    //Multiple resolutions are supported using different CE_PIXEL rates.
    //Must be based on CLK_VIDEO
    output        CE_PIXEL,

    //Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
    output  [7:0] VIDEO_ARX,
    output  [7:0] VIDEO_ARY,

    // These video signals are defined in sys_top.v, via the video_mixer we output the video from the emulator onto these
    // signals, which then get passed as follows:
    // emu -> video_mixer -> vga_osd -> vga_out
    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,    // = ~(VBlank | HBlank)

    output        LED_USER,  // 1 - ON, 0 - OFF.

    // b[1]: 0 - LED status is system status OR'd with b[0]
    //       1 - LED status is controled solely by b[0]
    // hint: supply 2'b00 to let the system control the LED.
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,
    output  [7:0] LED_MB,

    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
    output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
//  input         TAPE_IN,

    // SD-SPI
//  output        SD_SCK,
//  output        SD_MOSI,
//  input         SD_MISO,
//  output        SD_CS,
//  input         SD_CD,

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
    output        DDRAM_WE

    //SDRAM interface with lower latency
//  ,output        SDRAM_CLK,
//  output        SDRAM_CKE,
//  output [12:0] SDRAM_A,
//  output  [1:0] SDRAM_BA,
//  inout  [15:0] SDRAM_DQ,
//  output        SDRAM_DQML,
//  output        SDRAM_DQMH,
//  output        SDRAM_nCS,
//  output        SDRAM_nCAS,
//  output        SDRAM_nRAS,
//  output        SDRAM_nWE
);

//assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
//assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
 
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3; 

wire [2:0] scale = status[4:2];

// Menu is handled in the MiSTer c++ program.
//
`include "build_id.v" 
localparam CONF_STR =
{
        "SHARP MZ SERIES;;",
        "J,Fire;",
        "V,v1.01.",`BUILD_DATE
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
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;
wire        forced_scandoubler;

hps_io #(.STRLEN(($size(CONF_STR)>>3))) hps_io
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

sharpmz sharp_mz
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
//assign CLK_VIDEO = clk_sys;
assign CLK_VIDEO = clk_video_in;
assign CE_PIXEL  = clk_video_in;

//video_mixer #(.HALF_DEPTH(0)) video_mixer
video_mixer #(.LINE_LENGTH(320), .HALF_DEPTH(1)) video_mixer
(
    .clk_sys(clk_sys),
    .ce_pix(clk_video_in),                                                      // Video pixel clock from core.
    //.ce_pix_out(CE_PIXEL),

    .scanlines({scale == 4, scale == 3, scale == 2}),
    .scandoubler(scale || forced_scandoubler),
    .hq2x(scale==1),

    .mono(0),

    // Input signals into the mixer, originating from the emulator.
    .R(R_emu),
    .G(G_emu),
    .B(B_emu),

    // Positive pulses.
    .HSync(hsync_emu),
    .VSync(vsync_emu),
    .HBlank(hblank_emu),
    .VBlank(vblank_emu),

    .VGA_R(VGA_R),
    .VGA_G(VGA_G),
    .VGA_B(VGA_B),
    .VGA_VS(VGA_VS),
    .VGA_HS(VGA_HS),
    .VGA_DE(VGA_DE)

    // Outputs of the mixer are bound to the VGA_x signals defined in the sys_top module and passed into this module as parameters.
    // These signals then feed the vga_osd -> vga_out modules in systop.v
);

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
