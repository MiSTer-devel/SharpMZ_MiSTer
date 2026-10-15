`timescale 1ns/1ns
//
// Simulation top for the SharpMZ core.
//
// The machine is rtl/sharpmz_top.sv, the same module SharpMZ.sv (the MiSTer emu) instantiates between hps_io and
// video_mixer, so the simulation has the hardware's configuration logic, download routing and reset wiring. The C++
// harness (sim_headless.cpp) plays the part of Main and hps_io: it sets the 128-bit OSD status word (from the sim's
// options and --osd NAME=VALUE, decoded from SharpMZ.sv's CONF_STR), sends downloads with their file index as Main
// does, and serves the image slots. A behavioural DDR3 holds the tape data buffer.
//
// The core (rtl/sharpmz.vhd and everything below it) is a Verilog netlist made by "ghdl synth" (see the Makefile);
// its RAMs and ROMs are rtl_v/dpram.v and rtl_v/dprom.v.
//
`ifndef SIM_CLK_DIV
`define SIM_CLK_DIV 1
`endif
module top(
   input         clk_sys /*verilator public_flat*/,
   input         reset /*verilator public_flat*/,

   // hps_io
   input  [127:0] status,        // the OSD status word
   input  [1:0]  buttons,        // [1]: USER button / LCtrl+LAlt+RAlt (warm reset)
   input  [10:0] ps2_key,
   input  [5:0]  joy0,           // joystick 1, MiSTer order (5 fire 2, 4 fire 1, 3 up, 2 down, 1 left, 0 right)
   input  [31:0] prn_baud,       // uart_speed from Main

   input         ioctl_download,
   input  [15:0] ioctl_index,    // the OSD file slot (F1 tape to CMT, F2 direct, F3 system ROM, ...), as Main sends it
   input         ioctl_wr,
   input         ioctl_rd,
   input  [26:0] ioctl_addr,     // the offset in the file, as Main sends it
   input  [7:0]  ioctl_dout,
   output        ioctl_wait /*verilator public_flat*/,   // hold the download (tape data buffer in DDR3 busy)
   output [7:0]  ioctl_din,

   output [7:0]  VGA_R /*verilator public_flat*/,
   output [7:0]  VGA_G /*verilator public_flat*/,
   output [7:0]  VGA_B /*verilator public_flat*/,
   output        VGA_HS /*verilator public_flat*/,
   output        VGA_VS /*verilator public_flat*/,
   output        VGA_HB /*verilator public_flat*/,
   output        VGA_VB /*verilator public_flat*/,
   output        ce_pix /*verilator public_flat*/,

   output        AUDIO_L /*verilator public_flat*/,    // the 1-bit sound (8253 / tape), before the mix
   output [13:0] AUDIO_PSG /*verilator public_flat*/,  // MZ-800 PSG / MZ-1500 left PSG
   output [15:0] AUDIO_OUT_L /*verilator public_flat*/,  // the core's final audio (sharpmz_top audio_l/r: unsigned, as
   output [15:0] AUDIO_OUT_R /*verilator public_flat*/,  // SharpMZ.sv gives the framework with AUDIO_S = 0)
   output        prn_txd /*verilator public_flat*/,

   output [15:0] cpu_pc /*verilator public_flat*/,
   output        cpu_ce /*verilator public_flat*/,
   output        cpu_m1_n /*verilator public_flat*/,
   output        dbg_io_wr /*verilator public_flat*/,
   output        dbg_io_rd /*verilator public_flat*/,
   output [7:0]  dbg_io_port /*verilator public_flat*/,
   output [7:0]  dbg_io_data /*verilator public_flat*/,
   output [3:0]  dbg_m8_dmd /*verilator public_flat*/,
   output [7:0]  leds /*verilator public_flat*/,
   output        dbg_sysreset /*verilator public_flat*/,
   output [5:0]  dbg_delay /*verilator public_flat*/,
   output        dbg_rm /*verilator public_flat*/,
   output        dbg_warm /*verilator public_flat*/,
   output        dbg_wait_n /*verilator public_flat*/,
   output        dbg_vwait_n /*verilator public_flat*/,
   output [70:0] dbg_config /*verilator public_flat*/,
   output [7:0]  dbg_model /*verilator public_flat*/,   // the core's model code (sharpmz_top cfg_reg0_model)
   output        dbg_mz1500 /*verilator public_flat*/,

   // Image slots, driven by the harness (it serves one at a time; hps_io shares sd_buff_* and img_size the same way).
   input         img_mounted,    // S0 tape image
   input         img_readonly,
   input  [63:0] img_size,
   output [31:0] sd_lba,
   output        sd_rd,
   output        sd_wr,
   input         sd_ack,
   input  [8:0]  sd_buff_addr,
   input  [7:0]  sd_buff_dout,
   output [7:0]  sd_buff_din,
   input         sd_buff_wr,
   input         tape_rewind,    // OSD Rewind Tape Image (status bit 31), held for one frame
   input         fdd_mounted,    // S1 floppy drive A
   input         fdd_readonly,
   input  [63:0] fdd_size,
   output [31:0] fdd_lba,
   output        fdd_rd,
   output        fdd_wr,
   input         fdd_ack,
   output [7:0]  fdd_buff_din,
   input         fdd2_mounted,   // S2 floppy drive B (fdd_size / fdd_readonly as drive A)
   output [31:0] fdd2_lba,
   output        fdd2_rd,
   output        fdd2_wr,
   input         fdd2_ack,
   output [7:0]  fdd2_buff_din,
   input         qd_mounted,     // S3 Quick Disk
   input  [63:0] qd_size,
   output [31:0] qd_lba,
   output        qd_rd,
   output        qd_wr,
   input         qd_ack,
   input         qd_readonly,
   output [7:0]  qd_buff_din,

   output        fdd_busy /*verilator public_flat*/,
   output        tape_active /*verilator public_flat*/,
   output        tape_full /*verilator public_flat*/,
   output [7:0]  tape_record /*verilator public_flat*/,
   output [13:0] cmt_status /*verilator public_flat*/,
   output [7:0]  dbg_cmt_ctrl /*verilator public_flat*/,
   output [31:0] dbg_cmt_debug /*verilator public_flat*/,
   output [4:0]  dbg_tape_rs /*verilator public_flat*/,   // {XMIT_RAM_TYPE, TAPE_READ_STATE} of the CMT transmitter
   output [31:0] dbg_rcv /*verilator public_flat*/,
   output [31:0] dbg_rcv_sum /*verilator public_flat*/,
   output        dbg_pc1 /*verilator public_flat*/,
   output        dbg_readbit /*verilator public_flat*/,
   output        dbg_snd_en /*verilator public_flat*/,
   output        dbg_snd /*verilator public_flat*/,
   output        dbg_bde /*verilator public_flat*/,
   output [2:0]  dbg_map /*verilator public_flat*/,
   output        dbg_memwr /*verilator public_flat*/,
   output        dbg_memrd /*verilator public_flat*/,
   output [15:0] dbg_addr /*verilator public_flat*/,
   output [7:0]  dbg_wdata /*verilator public_flat*/,
   output [7:0]  dbg_rdata /*verilator public_flat*/,   // CPU data in
   output [1:0]  dbg_m8map /*verilator public_flat*/,
   output [16:0] dbg_qdpos /*verilator public_flat*/,   // Quick Disk head position
   output [1:0]  dbg_qdfifo /*verilator public_flat*/,  // Quick Disk SIO receive FIFO count
   output        dbg_qdovr /*verilator public_flat*/,   // Quick Disk SIO overrun flag
   output [7:0]  dbg_qdwr3 /*verilator public_flat*/,   // MZ-800 map: {CG-RAM/VRAM in (CGV), ROM at E000 (ROME)}
   output [1:0]  dbg_cse /*verilator public_flat*/,

   // Backdoor reads of internal memories for --ascii-end and --dump-mem.
   input  [11:0] vram_addr,
   output [7:0]  vram_q,
   input  [15:0] sysram_addr,
   output [7:0]  sysram_q
);

   // The image slots as hps_io presents them: one mount pulse per slot, a shared size / read-only.
   wire [3:0]  slot_mounted = {qd_mounted, fdd2_mounted, fdd_mounted, img_mounted};
   // hps_io keeps img_size / img_readonly at the last mounted image's values; the floppy reads them after the pulse.
   wire [63:0] mount_size = img_mounted ? img_size : (fdd_mounted | fdd2_mounted) ? fdd_size : qd_size;
   wire        mount_ro   = img_mounted ? img_readonly : (fdd_mounted | fdd2_mounted) ? fdd_readonly : qd_readonly;
   reg  [63:0] last_size = 0;
   reg         last_ro = 0;
   always @(posedge clk_sys) if (|slot_mounted) begin last_size <= mount_size; last_ro <= mount_ro; end
   wire [63:0] slot_size = |slot_mounted ? mount_size : last_size;
   wire        slot_ro   = |slot_mounted ? mount_ro : last_ro;
   wire [31:0] slot_lba[4];
   wire [3:0]  slot_rd, slot_wr;
   wire [7:0]  slot_buff_din[4];
   assign sd_lba = slot_lba[0];   assign sd_rd = slot_rd[0];   assign sd_wr = slot_wr[0];   assign sd_buff_din = slot_buff_din[0];
   assign fdd_lba = slot_lba[1];  assign fdd_rd = slot_rd[1];  assign fdd_wr = slot_wr[1];  assign fdd_buff_din = slot_buff_din[1];
   assign fdd2_lba = slot_lba[2]; assign fdd2_rd = slot_rd[2]; assign fdd2_wr = slot_wr[2]; assign fdd2_buff_din = slot_buff_din[2];
   assign qd_lba = slot_lba[3];   assign qd_rd = slot_rd[3];   assign qd_wr = slot_wr[3];   assign qd_buff_din = slot_buff_din[3];

   // DDR3 model: 64 KB at the tape buffer's address; BUSY now and then, reads answered 6-21 clocks later.
   wire        ddr_busy, ddr_rd, ddr_we, ddr_dout_ready;
   wire [28:0] ddr_addr;
   wire [63:0] ddr_din, ddr_dout;
   wire [7:0]  ddr_be, ddr_burst;
   reg  [63:0] ddr_mem[0:8191];
   reg  [15:0] ddr_lfsr = 16'hACE1;
   reg   [4:0] ddr_wait = 0;
   reg         ddr_pend = 0, ddr_rdy = 0;
   reg  [12:0] ddr_raddr;
   reg  [63:0] ddr_q;
   assign ddr_busy       = ddr_lfsr[0] & ddr_lfsr[3];               // a quarter of the clocks
   assign ddr_dout       = ddr_q;
   assign ddr_dout_ready = ddr_rdy;
   integer k;
   always @(posedge clk_sys) begin
      ddr_lfsr <= {ddr_lfsr[14:0], ddr_lfsr[15] ^ ddr_lfsr[13] ^ ddr_lfsr[12] ^ ddr_lfsr[10]};
      ddr_rdy  <= 0;
      if (!ddr_busy && ddr_we)
         for (k = 0; k < 8; k = k + 1) if (ddr_be[k]) ddr_mem[ddr_addr[12:0]][k*8 +: 8] <= ddr_din[k*8 +: 8];
      if (!ddr_busy && ddr_rd && !ddr_pend) begin
         ddr_pend <= 1; ddr_raddr <= ddr_addr[12:0]; ddr_wait <= 5'd6 + {1'b0, ddr_lfsr[7:4]};
      end
      else if (ddr_pend) begin
         if (ddr_wait != 0) ddr_wait <= ddr_wait - 1'd1;
         else begin ddr_q <= ddr_mem[ddr_raddr]; ddr_rdy <= 1; ddr_pend <= 0; end
      end
   end

   // OSD Rewind Tape Image is status bit 31; the harness's tape_rewind sets it.
   wire [127:0] status_in = status | ({127'd0, tape_rewind} << 31);
   wire [15:0]  aud_l, aud_r;
   wire         uart_txd;

   sharpmz_top #(
      .CLK_HZ(70937600 / `SIM_CLK_DIV),
      .QD_BYTE_CLKS(5583 / `SIM_CLK_DIV),
      .FONT_FILE("../rtl/software/mif/tape_osd_font.hex"),
      .A2D_FILE("../rtl/software/mif/tape_osd_a2d.hex")
   ) sm (
      .clk_sys(clk_sys), .reset(reset),
      .status(status_in), .buttons(buttons), .ps2_key(ps2_key), .joy0(joy0), .joy1(6'd0), .uart_speed(prn_baud),
      .hps_ioctl_download(ioctl_download), .hps_ioctl_upload(1'b0), .hps_ioctl_index(ioctl_index),
      .hps_ioctl_wr(ioctl_wr), .hps_ioctl_rd(ioctl_rd), .hps_ioctl_addr(ioctl_addr), .hps_ioctl_dout(ioctl_dout),
      .hps_ioctl_din(ioctl_din), .hps_ioctl_wait(ioctl_wait),
      .img_mounted(slot_mounted), .img_readonly(slot_ro), .img_size(slot_size),
      .sd_lba(slot_lba), .sd_rd(slot_rd), .sd_wr(slot_wr), .sd_ack({qd_ack, fdd2_ack, fdd_ack, sd_ack}),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(slot_buff_din), .sd_buff_wr(sd_buff_wr),
      .DDRAM_BUSY(ddr_busy), .DDRAM_BURSTCNT(ddr_burst), .DDRAM_ADDR(ddr_addr), .DDRAM_DOUT(ddr_dout),
      .DDRAM_DOUT_READY(ddr_dout_ready), .DDRAM_RD(ddr_rd), .DDRAM_DIN(ddr_din), .DDRAM_BE(ddr_be), .DDRAM_WE(ddr_we),
      .ce_pix(ce_pix), .vga_r(VGA_R), .vga_g(VGA_G), .vga_b(VGA_B),
      .vga_hs(VGA_HS), .vga_vs(VGA_VS), .vga_hb(VGA_HB), .vga_vb(VGA_VB),
      .audio_l(aud_l), .audio_r(aud_r),
      .uart_txd(uart_txd), .led_user(), .led_disk()
   );

   assign AUDIO_L      = sm.audio_l_emu;
   assign AUDIO_OUT_L  = aud_l;
   assign AUDIO_OUT_R  = aud_r;
   assign AUDIO_PSG    = sm.audio_psg;
   assign prn_txd      = uart_txd;
   assign fdd_busy     = sm.fdd_busy;
   assign tape_active  = sm.tape_active;
   assign tape_full    = sm.tape_full;
   assign tape_record  = sm.tape_record;
   assign cmt_status   = sm.cmt_status;
   assign dbg_cmt_ctrl = sm.cmt_ctrl;
   assign dbg_cmt_debug = sm.cmt_debug;
   assign dbg_model    = sm.cfg_reg0_model;
   assign dbg_mz1500   = sm.cfg_mz1500;

   // Debug taps into the netlist; ghdl keeps register and port names.
   assign leds = sm.main_leds;
   assign cpu_pc = sm.core.cpu0.u0.pc;
   assign cpu_ce = sm.core.clkgen0.ckencpui;
   assign cpu_m1_n = sm.core.cpu0.u0.m1_n;
   assign dbg_tape_rs = {sm.core.tape0.xmit_ram_type, sm.core.tape0.tape_read_state};
   assign dbg_io_wr = ~sm.core.t80_iorq_n & ~sm.core.t80_wr_n;
   assign dbg_io_rd = ~sm.core.t80_iorq_n & ~sm.core.t80_rd_n;
   wire bdr_hb, bdr_vb;
   mz800_border bdr(.clk(clk_sys), .ce_pix(ce_pix), .enable(1'b1), .hblank(sm.hblank_emu), .vblank(sm.vblank_emu), .bcol(4'd1),
                    .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .r_out(), .g_out(), .b_out(), .hblank_out(bdr_hb), .vblank_out(bdr_vb));
   assign dbg_bde = ~(bdr_hb | bdr_vb);
   assign dbg_snd_en = sm.core.mz80hw.sound_enable;        // 8253 GATE0 (E008 bit 0)
   assign dbg_snd    = sm.core.mz80hw.sound_pulse_x2;      // 8253 OUT0
   assign dbg_memwr  = ~sm.core.t80_mreq_n & ~sm.core.t80_wr_n;
   assign dbg_memrd  = ~sm.core.t80_mreq_n & ~sm.core.t80_rd_n;
`ifdef KEYDBG
   // Keyboard debug: every change of what the CPU reads from E001 (8255 PB, the key data) with the row (E000 write).
   reg [7:0] kd_last = 8'hAA, kd_row = 0;
   always @(posedge clk_sys) begin
      if (~sm.core.t80_mreq_n & ~sm.core.t80_wr_n & sm.core.t80_a16 == 16'hE000) kd_row <= sm.core.t80_do;
      if (~sm.core.t80_mreq_n & ~sm.core.t80_rd_n & sm.core.t80_a16 == 16'hE001 && sm.core.t80_di != kd_last) begin
         $display("keydbg: row %02x reads %02x", kd_row, sm.core.t80_di);
         kd_last <= sm.core.t80_di;
      end
   end
`endif
   assign dbg_addr   = sm.core.t80_a16;
   assign dbg_wdata  = sm.core.t80_do;
   assign dbg_rdata  = sm.core.t80_di;
   assign dbg_m8map  = {sm.core.mz80hw.m8_cgv, sm.core.mz80hw.m8_rome};
   assign dbg_qdpos  = sm.mz_qdisk.pos;
   assign dbg_qdfifo = sm.mz_qdisk.rx_cnt;
   assign dbg_qdovr  = sm.mz_qdisk.overrun;
   assign dbg_qdwr3  = sm.mz_qdisk.wa[3];
   assign dbg_cse    = {sm.core.mz80hw.cs_e_ni, sm.core.mz80hw.cs_e2_n};
   assign dbg_map    = {sm.core.mz80hw.mz_gram_enable, sm.core.mz80hw.mz_high_ram_inhibit, sm.core.mz80hw.mz_high_ram_enable};
   assign dbg_io_port = sm.core.t80_a16[7:0];
   assign dbg_io_data = sm.core.t80_do;
   assign dbg_m8_dmd = sm.core.mz80hw.m8_dmd;
   assign dbg_sysreset = sm.core.mz_system_reset;
   assign dbg_delay = sm.core.ctrl0.delay;
   assign dbg_rm = sm.core.ctrl0.reset_machine;
   assign dbg_warm = sm.core.ctrl0.warm_reset;
   assign dbg_wait_n = sm.core.t80_wait_n;
   assign dbg_vwait_n = sm.core.video_wait_n;
   assign dbg_config = sm.core.config_v;
   // CMT record FSM: {rcv_ram_state, rcv_state, recseq, type, error, try, success, done, ready_set}
   assign dbg_rcv = {15'd0, sm.core.tape0.rcv_ram_state, sm.core.tape0.rcv_state, sm.core.tape0.recseq,
                     sm.core.tape0.rcv_type, sm.core.tape0.rcv_error, sm.core.tape0.rcv_ram_try,
                     sm.core.tape0.rcv_ram_success, sm.core.tape0.rcv_done, sm.core.tape0.record_ready_set};
   assign dbg_rcv_sum = {sm.core.tape0.rcv_ram_checksum, sm.core.tape0.rcv_checksum};
   assign dbg_pc1 = sm.core.mz80hw.i8255_pc_o[1];
   assign dbg_readbit = sm.core.tape0.readbit;

   // v2 VideoController VRAM: four byte lanes, byte address = lane + 4 * index.
   wire [7:0] vl0 = sm.core.video0.vc.vram0.lanes_n1_ram.mem[vram_addr[11:2]];
   wire [7:0] vl1 = sm.core.video0.vc.vram0.lanes_n2_ram.mem[vram_addr[11:2]];
   wire [7:0] vl2 = sm.core.video0.vc.vram0.lanes_n3_ram.mem[vram_addr[11:2]];
   wire [7:0] vl3 = sm.core.video0.vc.vram0.lanes_n4_ram.mem[vram_addr[11:2]];
   assign vram_q = vram_addr[1:0] == 2'd0 ? vl0 : vram_addr[1:0] == 2'd1 ? vl1 : vram_addr[1:0] == 2'd2 ? vl2 : vl3;
   assign sysram_q = sm.core.sysram.mem[sysram_addr];

endmodule
