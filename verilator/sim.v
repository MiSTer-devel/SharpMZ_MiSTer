`timescale 1ns/1ns
//
// Simulation top for the SharpMZ core.
//
// The core (rtl/sharpmz.vhd and everything below it) is supplied as a Verilog
// netlist produced by "ghdl synth" -- see the Makefile. Its RAMs and ROMs are
// black boxes filled by rtl_v/dpram.v and rtl_v/dprom.v.
//
// This stands in for sharpmz.sv: the C++ harness drives the configuration
// inputs and the ioctl bus, including the MZF address mapping that sharpmz.sv
// does on hardware.
//
module top(
   input         clk_sys /*verilator public_flat*/,
   input         reset /*verilator public_flat*/,
   input         warm_reset /*verilator public_flat*/,

   output [7:0]  VGA_R /*verilator public_flat*/,
   output [7:0]  VGA_G /*verilator public_flat*/,
   output [7:0]  VGA_B /*verilator public_flat*/,
   output        VGA_HS /*verilator public_flat*/,
   output        VGA_VS /*verilator public_flat*/,
   output        VGA_HB /*verilator public_flat*/,
   output        VGA_VB /*verilator public_flat*/,
   output        ce_pix /*verilator public_flat*/,

   output        AUDIO_L /*verilator public_flat*/,
   output        AUDIO_R /*verilator public_flat*/,
   output [13:0] AUDIO_PSG /*verilator public_flat*/,

   input         ioctl_download,
   input         ioctl_direct,   // the download is a direct load (OSD Load Direct to RAM)
   input         direct_start_en,// Load Direct starts the program (OSD Load Direct: Start Program)
   input         ioctl_wr,
   input         ioctl_rd,
   input  [24:0] ioctl_addr,
   input  [7:0]  ioctl_dout,
   output        ioctl_wait /*verilator public_flat*/,   // hold the download (tape data buffer in DDR3 busy)
   output [7:0]  ioctl_din,

   input  [10:0] ps2_key,
   input  [5:0]  joy0,           // joystick 1, MiSTer order (5 fire 2, 4 fire 1, 3 up, 2 down, 1 left, 0 right)
   input         joy_1x03,       // MZ-1X03 joysticks connected (MZ-700/1500)
   input         key_sharp,      // OSD Keyboard Layout: 0 PC, 1 Sharp (by position)
   input         ramdisk_en,     // MZ-800 64 KB RAM disk
   input         prn_en,         // printer (OSD Printer: UART)
   input  [31:0] prn_baud,       // uart_speed from Main
   input         prn_ascii,      // OSD Printer Charset: ASCII
   output        prn_txd /*verilator public_flat*/,

   // Machine configuration, as sharpmz.sv derives it from the OSD status bits.
   input  [7:0]  cfg_model,
   input  [7:0]  cfg_display,
   input  [7:0]  cfg_display2,
   input  [7:0]  cfg_display3,
   input  [7:0]  cfg_cpu,
   input  [7:0]  cfg_audio,
   input  [7:0]  cfg_cmt,

   output [15:0] cpu_pc /*verilator public_flat*/,
   output        cpu_ce /*verilator public_flat*/,
   output        cpu_m1_n /*verilator public_flat*/,
   output        dbg_io_wr /*verilator public_flat*/,
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

   // Tape image slot (hps_io S0), driven by the harness.
   input         img_mounted,
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
   input         tape_rewind,
   // Floppy drive A (hps_io S1); the sd_buff_* bus above is shared, as in hps_io.
   input         fdd_mounted,
   input         fdd_readonly,
   input  [63:0] fdd_size,
   output [31:0] fdd_lba,
   output        fdd_rd,
   output        fdd_wr,
   input         fdd_ack,
   output [7:0]  fdd_buff_din,
   input         fdd2_mounted,
   input         fdd_b_unit2,    // drive B answers as unit 2 (OSD Drive B Unit: 3rd)   // floppy drive B (S2); shares fdd_size / fdd_readonly with drive A
   output [31:0] fdd2_lba,
   output        fdd2_rd,
   output        fdd2_wr,
   input         fdd2_ack,
   output [7:0]  fdd2_buff_din,
   input  [1:0]  fdc_mode,
   // Quick Disk (hps_io S3); shares sd_buff_*.
   input         qd_mounted,
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
   output [15:0] dbg_addr /*verilator public_flat*/,
   output [7:0]  dbg_wdata /*verilator public_flat*/,
   output [1:0]  dbg_cse /*verilator public_flat*/,

   // Backdoor reads of internal memories for --ascii-end and --dump-mem.
   input  [11:0] vram_addr,
   output [7:0]  vram_q,
   input  [15:0] sysram_addr,
   output [7:0]  sysram_q
);

   wire [31:0] din32;
   wire [24:0] tape_addr;
   wire        tape_wr;
   wire [7:0]  tape_dout;
   wire        tape_mounted;
   wire        ds_bus_active, ds_bus_wr;
   wire [24:0] ds_bus_addr;
   wire [7:0]  ds_bus_dout;
   wire        tape_rd, tape_b_busy;
   wire [7:0]  tape_b_dout;
   wire        tape_data_region;

   tape_image tape(
      .clk(clk_sys), .reset(reset | warm_reset),
      .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
      .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
      .rewind(tape_rewind), .host_busy(ioctl_download | ds_bus_active), .cmt_status(cmt_status),
      .active(tape_active), .bus_addr(tape_addr), .bus_wr(tape_wr), .bus_dout(tape_dout),
      .bus_din(tape_data_region ? tape_b_dout : din32[7:0]), .bus_busy(tape_b_busy), .bus_rd(tape_rd),
      .mounted(tape_mounted), .tape_full(tape_full), .record_no(tape_record)
   );

   // Same bus mux as sharpmz.sv.
   wire        mz_wr   = ioctl_download ? ioctl_wr   : ds_bus_active ? ds_bus_wr : tape_active & tape_wr;     // as sharpmz.sv: downloads first
   wire [24:0] mz_addr = ioctl_download ? ioctl_addr : ds_bus_active ? ds_bus_addr : tape_active ? tape_addr : 25'h1000000;
   wire [7:0]  mz_dout = ioctl_download ? ioctl_dout : ds_bus_active ? ds_bus_dout : tape_dout;

   wire        ds_inj_go, ds_m1_n, ds_mreq_n, ds_rd_n;
   wire [7:0]  ds_inj_data;
   direct_start #(.CLK_HZ(70937600 / `SIM_CLK_DIV)) dstart(
      .clk(clk_sys), .reset(reset), .enable(direct_start_en & (cfg_model[2:1] != 2'b11)),
      .is_mz800(cfg_model[2:0] == 3'd5), .has_e0(cfg_model[2]), .vblank(VGA_VB),
      .dl_active(ioctl_download & ioctl_direct), .dl_wr(mz_wr), .dl_addr(mz_addr), .dl_data(mz_dout),
      .bus_active(ds_bus_active), .bus_wr(ds_bus_wr), .bus_addr(ds_bus_addr), .bus_dout(ds_bus_dout),
      .m1_n(ds_m1_n), .mreq_n(ds_mreq_n), .rd_n(ds_rd_n), .inj_go(ds_inj_go), .inj_data(ds_inj_data));

   // Tape data buffer in DDR3, as sharpmz.sv, with a behavioural DDR3 below.
   assign tape_data_region = (mz_addr[24:16] == 9'h041);
   assign ioctl_wait = ioctl_download & tape_b_busy;
   wire [15:0] tapedata_addr;
   wire [7:0]  tapedata_wdata, tapedata_rdata;
   wire        tapedata_we, tapedata_ready;
   wire        ddr_busy, ddr_rd, ddr_we, ddr_dout_ready;
   wire [28:0] ddr_addr;
   wire [63:0] ddr_din, ddr_dout;
   wire [7:0]  ddr_be, ddr_burst;
   tape_ddr tddr(
      .clk(clk_sys), .reset(reset),
      .a_addr(tapedata_addr), .a_we(tapedata_we), .a_din(tapedata_wdata), .a_dout(tapedata_rdata), .a_ready(tapedata_ready),
      .b_addr(mz_addr[15:0]), .b_we(mz_wr & tape_data_region),
      .b_rd(~ioctl_download & tape_active & tape_rd & tape_data_region),
      .b_din(mz_dout), .b_dout(tape_b_dout), .b_busy(tape_b_busy),
      .DDRAM_CLK(), .DDRAM_BUSY(ddr_busy), .DDRAM_BURSTCNT(ddr_burst), .DDRAM_ADDR(ddr_addr), .DDRAM_DOUT(ddr_dout),
      .DDRAM_DOUT_READY(ddr_dout_ready), .DDRAM_RD(ddr_rd), .DDRAM_DIN(ddr_din), .DDRAM_BE(ddr_be), .DDRAM_WE(ddr_we));

   // DDR3 model: 64 KB at the tape buffer's address; BUSY now and then, reads answered 6-21 clocks later.
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
   wire        clksys_out, clkiop_unused;

   wire [7:0]  ext_io_addr, ext_io_dout, ext_io_din;
   wire        ext_io_rd, ext_io_wr, ext_io_oe, ext_int_n, ext_ce_cpu;
   wire [31:0] fdc_lba[2];
   wire [1:0]  fdc_rd, fdc_wr;
   wire [7:0]  fdc_buff_din[2];
   wire        fdc_present;
   wire [7:0]  fdc_io_din, qd_io_din;
   wire        fdc_io_oe, qd_io_oe, qd_busy;
   assign ext_io_oe  = fdc_io_oe | qd_io_oe;
   assign ext_io_din = fdc_io_oe ? fdc_io_din : qd_io_din;

`ifndef SIM_CLK_DIV
`define SIM_CLK_DIV 1
`endif
   mz_qdisk #(.BYTE_CLKS(5583 / `SIM_CLK_DIV)) qd(
      .clk_sys(clk_sys), .reset(reset | warm_reset),
      .enable(cfg_display3[3] | (cfg_model[2:0] == 3'b101 & qd_mounted_l)),       // MZ-1500; MZ-800 with an image
      .io_addr(ext_io_addr), .io_rd(ext_io_rd), .io_wr(ext_io_wr), .io_dout(ext_io_dout),
      .io_din(qd_io_din), .io_oe(qd_io_oe),
      .img_mounted(qd_mounted), .img_readonly(qd_readonly), .img_size(qd_size),
      .sd_lba(qd_lba), .sd_rd(qd_rd), .sd_wr(qd_wr), .sd_ack(qd_ack),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(qd_buff_din), .sd_buff_wr(sd_buff_wr),
      .busy(qd_busy)
   );
   reg qd_mounted_l = 0;
   always @(posedge clk_sys) if (qd_mounted) qd_mounted_l <= |qd_size;

   mz_fdc fdc(
      .clk_sys(clk_sys), .reset(reset | warm_reset), .ce_cpu(ext_ce_cpu),
      .model_ok(cfg_model[2] == 1'b1), .mode(fdc_mode), .crc_report(1'b0), .b_unit2(fdd_b_unit2),                          // MZ-700, MZ-800, MZ-80B, MZ-2000
      .io_addr(ext_io_addr), .io_rd(ext_io_rd), .io_wr(ext_io_wr), .io_dout(ext_io_dout),
      .io_din(fdc_io_din), .io_oe(fdc_io_oe), .int_n(ext_int_n),
      .img_mounted({fdd2_mounted, fdd_mounted}), .img_readonly(fdd_readonly), .img_size(fdd_size),
      .sd_lba(fdc_lba), .sd_rd(fdc_rd), .sd_wr(fdc_wr), .sd_ack({fdd2_ack, fdd_ack}),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(fdc_buff_din), .sd_buff_wr(sd_buff_wr),
      .busy(fdd_busy), .present(fdc_present)
   );
   assign fdd_lba = fdc_lba[0];
   assign fdd_rd = fdc_rd[0];
   assign fdd_wr = fdc_wr[0];
   assign fdd_buff_din = fdc_buff_din[0];
   assign fdd2_lba = fdc_lba[1];
   assign fdd2_rd = fdc_rd[1];
   assign fdd2_wr = fdc_wr[1];
   assign fdd2_buff_din = fdc_buff_din[1];

   sharpmz core(
      .CLKMASTER      (clk_sys),
      .COLD_RESET     (reset),
      .WARM_RESET     (warm_reset),
      .PS2_KEY        (ps2_key),
      .JOY0           (joy0),
      .JOY1           (6'd0),
      .JOY_1X03       (joy_1x03),
      .KEY_SHARP      (key_sharp),
      .RAMDISK_EN     (ramdisk_en),
      .TAPEDATA_ADDR  (tapedata_addr),
      .TAPEDATA_DOUT  (tapedata_wdata),
      .TAPEDATA_WE    (tapedata_we),
      .TAPEDATA_DIN   (tapedata_rdata),
      .TAPEDATA_READY (tapedata_ready),
      .INJ_GO         (ds_inj_go),
      .INJ_DATA       (ds_inj_data),
      .CPU_M1_n       (ds_m1_n),
      .CPU_MREQ_n     (ds_mreq_n),
      .CPU_RD_n       (ds_rd_n),
      .PRN_EN         (prn_en),
      .PRN_RDA        (prn_rda),
      .PRN_DATA       (prn_data),
      .PRN_STB        (prn_stb),
      .CFG_MODEL      (cfg_model),
      .CFG_DISPLAY    (cfg_display),
      .CFG_DISPLAY2   (cfg_display2),
      .CFG_DISPLAY3   (cfg_display3),
      .CFG_CPU        (cfg_cpu),
      .CFG_AUDIO      (cfg_audio),
      .CFG_CMT        (cfg_cmt),
      .CFG_USERROM    (cfg_display3[3] ? 8'h10 : 8'h00),                               // MZ-1500: E800-EFFF is always ROM
      .CFG_FDCROM     (((fdc_present & cfg_model[2:0] == 3'b100) | cfg_display3[3]) ? 8'h10 : 8'h00),   // MZ-700 FD ROM with the interface; MZ-1500 F000 ROM
      .IOCTL_DOWNLOAD (ioctl_download),
      .IOCTL_UPLOAD   (1'b0),
      .IOCTL_CLK      (clk_sys),
      .IOCTL_WR       (mz_wr),
      .IOCTL_RD       (ioctl_rd),
      .IOCTL_ADDR     (mz_addr),
      .IOCTL_DOUT     ({24'd0, mz_dout}),
      .CLKSYS         (clksys_out),
      .CLKVID         (ce_pix),
      .CLKIOP         (clkiop_unused),
      .MAIN_LEDS      (leds),
      .VGA_HB_O       (VGA_HB),
      .VGA_VB_O       (VGA_VB),
      .VGA_HS_O       (VGA_HS),
      .VGA_VS_O       (VGA_VS),
      .VGA_R_O        (VGA_R),
      .VGA_G_O        (VGA_G),
      .VGA_B_O        (VGA_B),
      .AUDIO_L_O      (AUDIO_L),
      .AUDIO_R_O      (AUDIO_R),
      .AUDIO_PSG_O    (AUDIO_PSG),
      .AUDIO_PSG_R_O  (),
      .CMT_STATUS     (cmt_status),
      .CMT_CTRL       (dbg_cmt_ctrl),
      .CMT_DEBUG      (dbg_cmt_debug),
      .EXT_IO_ADDR    (ext_io_addr),
      .EXT_IO_RD      (ext_io_rd),
      .EXT_IO_WR      (ext_io_wr),
      .EXT_IO_DOUT    (ext_io_dout),
      .EXT_IO_DIN     (ext_io_din),
      .EXT_IO_OE      (ext_io_oe),
      .EXT_INT_n      (ext_int_n),
      .EXT_CE_CPU     (ext_ce_cpu),
      .IOCTL_DIN      (din32)
   );

   assign ioctl_din = din32[7:0];

   // Debug taps into the netlist; ghdl keeps register and port names.
   assign cpu_pc = core.cpu0.u0.pc;
   assign cpu_ce = core.clkgen0.ckencpui;
   assign cpu_m1_n = core.cpu0.u0.m1_n;
   assign dbg_tape_rs = {core.tape0.xmit_ram_type, core.tape0.tape_read_state};
   assign dbg_io_wr = ~core.t80_iorq_n & ~core.t80_wr_n;
   mz800_border bdr(.clk(clk_sys), .ce_pix(ce_pix), .enable(1'b1), .hblank(VGA_HB), .vblank(VGA_VB), .bcol(4'd1),
                    .r_in(8'd0), .g_in(8'd0), .b_in(8'd0), .r_out(), .g_out(), .b_out(), .hblank_out(bdr_hb), .vblank_out(bdr_vb));
   wire bdr_hb, bdr_vb;
   assign dbg_bde = ~(bdr_hb | bdr_vb);

   wire       prn_rda, prn_stb;
   wire [7:0] prn_data;
   mz_printer #(.CLK_HZ(70937600 / `SIM_CLK_DIV)) prn(
      .clk(clk_sys), .reset(reset), .enable(prn_en), .ascii(prn_ascii), .rdp(prn_stb), .data(prn_data), .rda(prn_rda),
      .uart_speed(prn_baud), .txd(prn_txd), .count());
   assign dbg_snd_en = core.mz80hw.sound_enable;        // 8253 GATE0 (E008 bit 0)
   assign dbg_snd    = core.mz80hw.sound_pulse_x2;      // 8253 OUT0
   assign dbg_memwr  = ~core.t80_mreq_n & ~core.t80_wr_n;
`ifdef KEYDBG
   // Keyboard debug: every change of what the CPU reads from E001 (8255 PB, the key data) with the row (E000 write).
   reg [7:0] kd_last = 8'hAA, kd_row = 0;
   always @(posedge clk_sys) begin
      if (~core.t80_mreq_n & ~core.t80_wr_n & core.t80_a16 == 16'hE000) kd_row <= core.t80_do;
      if (~core.t80_mreq_n & ~core.t80_rd_n & core.t80_a16 == 16'hE001 && core.t80_di != kd_last) begin
         $display("keydbg: row %02x reads %02x", kd_row, core.t80_di);
         kd_last <= core.t80_di;
      end
   end
`endif
   assign dbg_addr   = core.t80_a16;
   assign dbg_wdata  = core.t80_do;
   assign dbg_cse    = {core.mz80hw.cs_e_ni, core.mz80hw.cs_e2_n};
   assign dbg_map    = {core.mz80hw.mz_gram_enable, core.mz80hw.mz_high_ram_inhibit, core.mz80hw.mz_high_ram_enable};
   assign dbg_io_port = core.t80_a16[7:0];
   assign dbg_io_data = core.t80_do;
   assign dbg_m8_dmd = core.mz80hw.m8_dmd;
   assign dbg_sysreset = core.mz_system_reset;
   assign dbg_delay = core.ctrl0.delay;
   assign dbg_rm = core.ctrl0.reset_machine;
   assign dbg_warm = core.ctrl0.warm_reset;
   assign dbg_wait_n = core.t80_wait_n;
   assign dbg_vwait_n = core.video_wait_n;
   assign dbg_config = core.config_v;
   // CMT record FSM: {rcv_ram_state, rcv_state, recseq, type, error, try, success, done, ready_set}
   assign dbg_rcv = {15'd0, core.tape0.rcv_ram_state, core.tape0.rcv_state, core.tape0.recseq,
                     core.tape0.rcv_type, core.tape0.rcv_error, core.tape0.rcv_ram_try,
                     core.tape0.rcv_ram_success, core.tape0.rcv_done, core.tape0.record_ready_set};
   assign dbg_rcv_sum = {core.tape0.rcv_ram_checksum, core.tape0.rcv_checksum};
   assign dbg_pc1 = core.mz80hw.i8255_pc_o[1];
   assign dbg_readbit = core.tape0.readbit;

   // v2 VideoController VRAM: four byte lanes, byte address = lane + 4 * index.
   wire [7:0] vl0 = core.video0.vc.vram0.lanes_n1_ram.mem[vram_addr[11:2]];
   wire [7:0] vl1 = core.video0.vc.vram0.lanes_n2_ram.mem[vram_addr[11:2]];
   wire [7:0] vl2 = core.video0.vc.vram0.lanes_n3_ram.mem[vram_addr[11:2]];
   wire [7:0] vl3 = core.video0.vc.vram0.lanes_n4_ram.mem[vram_addr[11:2]];
   assign vram_q = vram_addr[1:0] == 2'd0 ? vl0 : vram_addr[1:0] == 2'd1 ? vl1 : vram_addr[1:0] == 2'd2 ? vl2 : vl3;
   assign sysram_q = core.sysram.mem[sysram_addr];

endmodule
