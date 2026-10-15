//=======================================================================================================
//
// Name:            sharpmz_top.sv
// Description:     The SharpMZ machine with everything the MiSTer top level used to wire around it: the OSD status
//                  bits -> machine configuration, the download routing (file slots -> core addresses), the resets,
//                  the tape image engine, Load Direct start, the DDR3 tape buffer, the floppy and Quick Disk
//                  interfaces, the printer, the MZ-800 border and the tape message overlay.
//
//                  SharpMZ.sv (the MiSTer emu: hps_io, PLL, video_mixer) and verilator/sim.v both use this module,
//                  so the simulation takes the same OSD status word as the hardware and behaves the same, option by
//                  option (they used to wire these differently: the sim reset the floppy interface on a warm reset
//                  and the hardware didn't, which hid EeDee's MZ-80B Boot Reset hang).
//
// Copyright:       (C) 2026 The SharpMZ MiSTer contributors. GPL v3 or later.
//
//=======================================================================================================

module sharpmz_top #(
	parameter CLK_HZ       = 70937600,                 // clk_sys (the sim runs it slower: CLK_HZ / SIM_CLK_DIV)
	parameter QD_BYTE_CLKS = 5583,                     // Quick Disk byte time in clk_sys clocks
	parameter FONT_FILE    = "rtl/software/mif/tape_osd_font.hex",
	parameter A2D_FILE     = "rtl/software/mif/tape_osd_a2d.hex"
)
(
	input             clk_sys,
	input             reset,                           // cold: the core is loaded, the MiSTer reset button, PLL lock

	// hps_io
	input     [127:0] status,                          // the OSD status word (CONF_STR bits)
	input       [1:0] buttons,                         // [1]: USER button / LCtrl+LAlt+RAlt
	input      [10:0] ps2_key,
	input       [5:0] joy0,
	input       [5:0] joy1,
	input      [31:0] uart_speed,

	input             hps_ioctl_download,
	input             hps_ioctl_upload,
	input      [15:0] hps_ioctl_index,
	input             hps_ioctl_wr,
	input             hps_ioctl_rd,
	input      [26:0] hps_ioctl_addr,
	input       [7:0] hps_ioctl_dout,
	output      [7:0] hps_ioctl_din,
	output            hps_ioctl_wait,

	// Image slots: S0 tape image, S1/S2 floppy drives A/B, S3 Quick Disk.
	input       [3:0] img_mounted,
	input             img_readonly,
	input      [63:0] img_size,
	output     [31:0] sd_lba[4],
	output      [3:0] sd_rd,
	output      [3:0] sd_wr,
	input       [3:0] sd_ack,
	input       [8:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	output      [7:0] sd_buff_din[4],
	input             sd_buff_wr,

	// DDR3 (the tape data buffer, rtl/tape_ddr.sv).
	input             DDRAM_BUSY,
	output      [7:0] DDRAM_BURSTCNT,
	output     [28:0] DDRAM_ADDR,
	input      [63:0] DDRAM_DOUT,
	input             DDRAM_DOUT_READY,
	output            DDRAM_RD,
	output     [63:0] DDRAM_DIN,
	output      [7:0] DDRAM_BE,
	output            DDRAM_WE,

	// Video (after the MZ-800 border and the tape messages) and audio.
	output            ce_pix,
	output      [7:0] vga_r,
	output      [7:0] vga_g,
	output      [7:0] vga_b,
	output            vga_hs,
	output            vga_vs,
	output            vga_hb,
	output            vga_vb,
	output     [15:0] audio_l,
	output     [15:0] audio_r,

	output            uart_txd,                        // the printer (OSD Printer: UART)
	output            led_user,
	output            led_disk
);

wire [31:0] joystick_0 = {26'd0, joy0};
wire [31:0] joystick_1 = {26'd0, joy1};

wire        tape_active;
wire        tape_ram_load;                          // tape_image: Tape Image Start: Direct, first record going to RAM
wire        tape_msg;                               // tape_image -> tape_osd: what the tape did
wire  [1:0] tape_msg_kind;
wire  [7:0] tape_rec_total;
wire[127:0] tape_rec_name;
wire        tape_rec_qd;                            // the record is a Quick Disk BASIC file (tape_osd: "QD:")
wire        warm_reset_user;                        // the resets that also reset the tape engine (below)
reg         tape_ram_load_d = 0;
wire        ds_bus_active, ds_bus_wr, ds_inj_go;   // Load Direct start (direct_start, below)
wire [24:0] ds_bus_addr;
wire  [7:0] ds_bus_dout, ds_inj_data;
wire        cpu_m1_n, cpu_mreq_n, cpu_rd_n;
wire        tape_data_region, tape_rd, tape_b_busy;   // tape data buffer in DDR3 (tape_ddr, below)
wire  [7:0] tape_b_dout;

assign hps_ioctl_wait = hps_ioctl_download & tape_b_busy;   // Only while a byte of a tape download waits for DDR3.

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
			3'd0: mz_fast_tape = 3'b101; // Fastest (the default): the 32x step, capped at clk_sys/2 (about 35 MHz).
			3'd1: mz_fast_tape = 3'b000; // Off/original speed.
			3'd2: mz_fast_tape = 3'b001; // 2x.
			3'd3: mz_fast_tape = 3'b010; // 4x.
			3'd4: mz_fast_tape = 3'b011; // 8x.
			3'd5: mz_fast_tape = 3'b100; // 16x.
			default: mz_fast_tape = 3'b101; // 6 (the old 32x) and 7: Fastest.
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
wire [7:0] cfg_fdcrom  = (status[29] | cfg_mz1500 | (fdc_present & (cfg_model == 3'b100 | cfg_model == 3'b011))) ? (8'd1 << cfg_model) : 8'd0;  // MZ-700 / MZ-80A: the interface brings its ROM at F000 (MZ-1E05 / the MZ-80A interface ROM; the MZ-1500 has its own F000 ROM)

wire [7:0] cfg_reg0_model   = {5'd0, cfg_model};
wire [7:0] cfg_reg1_display = {1'b0, status[18], 1'b0, 1'b0, 1'b0, cfg_display};  // video and graphics always on  // PCG is software controlled (E010-E012).
wire [7:0] cfg_reg2_display = 8'd3;                    // Native timing (the video is native-only).
wire       cfg_japan = status[56] & (cfg_model == 3'b100) & ~cfg_mz1500;   // OSD Region: Japan (MZ-700: Japanese CG, monitor 1Z-009B, 60 Hz)
wire [7:0] cfg_reg3_display = {3'd0, cfg_japan, cfg_mz1500, status[32], 2'b00};   // 4: Japanese MZ-700. 3: MZ-1500. 2: MZ-800 rear mode switch (0 = MZ-700, as mz800emu's default; 1 = MZ-800).
// CPU Speed: Normal, 2x .. 16x, Fastest. The core's steps past a model's limit fall back to the original speed, so
// Fastest (and the old +6/+7) is that model's last step: 64 MHz on the MZ-80K/80C/1200/80A (5), 56/64 MHz elsewhere
// (4), both capped at clk_sys/2 (about 35 MHz).
wire [2:0] cpu_fastest      = cfg_model[2] ? 3'd4 : 3'd5;
wire [2:0] cfg_cpu_step     = (status[6:4] >= 3'd5) ? cpu_fastest : status[6:4];
wire [7:0] cfg_reg4_cpu     = {status[30], 4'd0, cfg_cpu_step};
wire [7:0] cfg_reg5_audio   = {7'd0, status[54:53] == 2'd2};     // Tape Sound: Only (the tape signal instead of the sound)
wire [7:0] cfg_reg6_cmt     = {1'b0, status[27], status[26], cfg_tape_buttons, cfg_fast_tape};
wire [7:0] cfg_reg8_userrom = cfg_userrom;
wire [7:0] cfg_reg9_fdcrom  = cfg_fdcrom;

/////////////////  DOWNLOAD ROUTING  //////////////

localparam [5:0] FILE_TAPE_CMT    = 6'd1;
localparam [5:0] FILE_TAPE_DIRECT = 6'd2;
localparam [5:0] FILE_SYSROM      = 6'd3;      // combined monitor ROM image, at 0x000000 (also index 0: boot.rom)
localparam [5:0] FILE_SYSRAM      = 6'd4;      // RAM image, at 0x100000
localparam [5:0] FILE_CGROM       = 6'd6;      // character generator ROM image, at 0x500000
wire        rom_slot;                          // the download is a ROM image (below)
localparam [24:0] IOCTL_SYSRAM_BASE = 25'h0100000;

reg hps_ioctl_download_d = 0;
reg [5:0] active_file_slot = 0;
assign rom_slot = active_file_slot == FILE_SYSROM || active_file_slot == FILE_CGROM || active_file_slot == 6'd0;
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
	if((hps_ioctl_download_d && !hps_ioctl_download && (active_file_slot == FILE_TAPE_DIRECT || rom_slot)) ||
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
// ROM images (Load System ROM / CGROM, boot.rom): the machine is held while they load, then reset as after a direct
// load, so it starts on the new ROM (Main reloads the remembered ones at every core start, with the CPU running).
wire        rom_load_active = hps_ioctl_download && rom_slot;
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
			// Main gives every file address 0 (a CONF_STR address only counts in DDR), so each image goes to its region here.
			FILE_SYSRAM:
				mz_ioctl_addr_map = 25'h0100000 + addr[24:0];
			FILE_CGROM:
				mz_ioctl_addr_map = 25'h0500000 + addr[24:0];
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
wire [31:0] cmt_debug;
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
	.msg(tape_msg), .msg_kind(tape_msg_kind), .rec_total(tape_rec_total), .rec_name(tape_rec_name), .rec_qd(tape_rec_qd),
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
direct_start #(.CLK_HZ(CLK_HZ)) direct_start
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
	.DDRAM_CLK(),
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

// OSD Reset (status[0]) is a pulse of a few microseconds (Main sets the bit and clears it at once); stretch any reset
// request to about 1 ms of clk_sys, so the core's asynchronously loaded reset one-shot (mctrl.vhd) gets a clean edge.
reg  [16:0] reset_stretch = 0;
always @(posedge clk_sys) begin
	if (status[0] | buttons[1]) reset_stretch <= 17'h1FFFF;
	else if (reset_stretch != 0) reset_stretch <= reset_stretch - 1'd1;
end
assign warm_reset_user = status[0] | buttons[1] | (reset_stretch != 0) | direct_load_active | rom_load_active | (direct_load_reset_ctr != 0);
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
// On the MZ-800/1500 everything is 3x the PSG's 14-bit mix: one channel at full volume was 1/16 of full scale
// (testers: "extremely low"); now four channels and the beeper at full volume reach 61428 of 65535.
wire        has_psg = (cfg_model == 3'b101) | cfg_mz1500;
wire [15:0] beep_l  = has_psg ? (audio_l_emu ? 16'd12288 : 16'd0) : {1'b0, audio_l_emu, 14'd0};
wire [15:0] beep_r  = has_psg ? (audio_r_emu ? 16'd12288 : 16'd0) : {1'b0, audio_r_emu, 14'd0};
wire [15:0] psg_l   = {2'b00, audio_psg} + {1'b0, audio_psg, 1'b0};       // x3
wire [15:0] psg_r   = {2'b00, audio_psg_r} + {1'b0, audio_psg_r, 1'b0};
// Tape Sound: the tape signal (playback, cmt_status[6]; recording, cmt_ctrl[0]) mixed in quietly while the tape
// moves (cmt_status[4]), like a deck's monitor speaker; Audio Source = Tape plays it instead of the sound.
wire        tape_bit = cmt_status[4] & (cmt_status[6] | cmt_ctrl[0]);
wire [15:0] tape_snd = (status[54:53] == 2'd1 && tape_bit) ? 16'h0800 : 16'd0;   // Tape Sound: Mix

// Printer (OSD Printer: UART): the MZ-700 / MZ-800 / MZ-1500 printer port, sent out of the MiSTer UART for the
// printer daemon (rtl/mz_printer.sv).
wire        prn_rda, prn_stb, prn_txd;
wire  [7:0] prn_data;
mz_printer #(.CLK_HZ(CLK_HZ)) mz_printer
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
assign uart_txd = status[47] ? prn_txd : 1'b1;
assign audio_l = beep_l + psg_l + tape_snd;
assign audio_r = beep_r + psg_r + tape_snd;

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
wire       fdc_wait;                                // MZ-80A floppy interface: CPU WAIT at F3FE (mz_fdc)
wire [31:0] fdc_lba[2];
wire [7:0]  fdc_buff_din[2];

mz_fdc mz_fdc
(
	.clk_sys(clk_sys),
	.reset(reset | warm_reset_user),            // the machine's reset line resets the interface too (the mounted images stay)
	.ce_cpu(ext_ce_cpu),
	.model_ok(cfg_model[2] | cfg_model == 3'b011), // MZ-700, MZ-800, MZ-80B, MZ-2000 and the MZ-80A (same FDC ports)
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
	.wait_req(fdc_wait),
	.present(fdc_present)
);
// Quick Disk (MZ-1500 built in; MZ-800 MZ-1F11 when an image is mounted) on image slot S3.
wire [7:0] fdc_io_din, qd_io_din;
wire       fdc_io_oe, qd_io_oe, qd_busy;
reg        qd_mounted = 0;
always @(posedge clk_sys) if (img_mounted[3]) qd_mounted <= |img_size;
assign ext_io_oe  = fdc_io_oe | qd_io_oe;
assign ext_io_din = fdc_io_oe ? fdc_io_din : qd_io_din;

mz_qdisk #(.BYTE_CLKS(QD_BYTE_CLKS)) mz_qdisk
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

sharpmz core
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
	.CMT_DEBUG(cmt_debug),                                // for the simulation (unused here)
	.EXT_IO_ADDR(ext_io_addr),
	.EXT_IO_RD(ext_io_rd),
	.EXT_IO_WR(ext_io_wr),
	.EXT_IO_DOUT(ext_io_dout),
	.EXT_IO_DIN(ext_io_din),
	.EXT_IO_OE(ext_io_oe),
	.EXT_INT_n(ext_int_n),
	.EXT_FDC_WAIT(fdc_wait),
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

assign led_user = hps_ioctl_download;
assign led_disk = tape_active | cmt_status[4] | fdd_busy | qd_busy;    // Tape image, CMT, floppy or Quick Disk activity.

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

// Tape image messages over the picture (OSD Tape Messages): where the tape is, for three seconds after it moves.
wire [7:0] R_osd, G_osd, B_osd;
tape_osd #(.CLK_HZ(CLK_HZ), .FONT_FILE(FONT_FILE), .A2D_FILE(A2D_FILE)) tape_osd
(
	.clk(clk_sys),
	.ce_pix(clk_video_in),
	.enable(~status[55]),
	.hblank(hblank_brd), .vblank(vblank_brd),
	.r_in(R_brd), .g_in(G_brd), .b_in(B_brd),
	.r_out(R_osd), .g_out(G_osd), .b_out(B_osd),
	.show(tape_msg),
	.kind(tape_msg_kind),
	.rec_no(tape_msg_kind == 2'd2 ? tape_rec_total - 1'd1 : tape_record),
	.rec_total(tape_rec_total),
	.name(tape_rec_name),
	.qd_file(tape_rec_qd & cfg_mz1500)
);


assign ce_pix = clk_video_in;
assign vga_r  = R_osd;
assign vga_g  = G_osd;
assign vga_b  = B_osd;
assign vga_hs = hsync_emu;
assign vga_vs = vsync_emu;
assign vga_hb = hblank_brd;
assign vga_vb = vblank_brd;

endmodule
