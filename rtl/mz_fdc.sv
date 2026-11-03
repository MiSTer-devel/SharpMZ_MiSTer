//============================================================================
//
//  Sharp MZ-800 / MZ-700 floppy disk interface (MZ-1E05 style) with two drives.
//
//  Ports (Sharp MZ-800 Technical Reference, MZ-1E05 service manual, mz800emu fdc.c):
//    D8-DB  MB8876A (WD1791 family): status/command, track, sector, data.
//           The data bus between the CPU and the chip is inverted, both ways.
//    DC     bit 7 motor; bit 2 set loads the drive number from bits 1:0.
//    DD     bit 0 side (used as written, 0 = DSK side 0).
//    DE     density (ignored).
//    DF     bit 0 EINT (MZ-800 "HD patch"): /INT = EINT and DRQ. CP/M 4.1 reads and writes
//           every byte in the interrupt routine.
//    Reads of DC-DF return FF (not driven).
//
//  The chip is Sorgelig's wd1793.sv (from FM-7_MiSTer), one instance per drive, reading
//  Extended CPC DSK images through the MiSTer image slots. Commands go to the selected
//  drive; track/sector/data writes go to both, because a real controller has one
//  register set that CP/M saves and restores across drive changes.
//
//  MZ-80K / 80C / 1200 (k_mode): the MZ-80FIO interface with a Toshiba T3444M controller, as
//  Takeda's CSCP models it (src/vm/mz80k/mz80fio.cpp, src/vm/t3444a.cpp) and its boot ROM uses it
//  (software/idealine/mz-80k/mz80kfdif):
//    F8     write: sector (bits 6:0) and side (bit 7). IN (C): B bit 2 loads the drive from bits 1:0,
//           bit 3 motor, bit 4 TND (end a multi-sector read or write after the current sector).
//    F9     write: track. Read: bit 2 DRDY (disk in and motor on), bit 1 CRDY (controller ready),
//           bit 0 RQM (a data byte is ready, or wanted).
//    FA     write: command in bits 7:4. Read: status in bits 7:4 (bit 7 ready, 6:4 the result).
//    FB     data.
//  Disks are 35 or 40 tracks, 2 sides, 16 sectors of 128 bytes, single density. A sequencer here runs
//  each T3444 command on the selected drive's wd1793 (restore, seek, read or write sector, the next
//  sector until TND); during a transfer the CPU's FB accesses go straight to the chip's data register.
//
//  Copyright (C) 2026 SharpMZ MiSTer contributors. GPL v2 or later.
//
//============================================================================

module mz_fdc
(
	input         clk_sys,
	input         reset,
	input         ce_cpu,         // CPU clock enable; the controller timing runs at CPU speed
	input         model_ok,       // Model has the interface (MZ-700/800, MZ-80B/2000)
	input         k_mode,         // MZ-80K / 80C / 1200: the MZ-80FIO interface at F8-FB instead
	input   [1:0] mode,           // 0 Auto (present while a disk image is mounted), 1 On, 2 Off
	input         crc_report,     // Report sectors dumped with a CRC error (else read them as good)

	// Z80 I/O
	input   [7:0] io_addr,
	input   [7:0] io_addr_hi,     // A15-A8 (B for IN r,(C)): the MZ-80FIO's drive, motor and TND
	input         io_rd,
	input         io_wr,
	input   [7:0] io_dout,        // CPU data out
	output  [7:0] io_din,         // data for the CPU
	output        io_oe,          // this device answers the current read
	output        int_n,

	// MiSTer image slots, one per drive
	input   [1:0] img_mounted,
	input         eject,          // the machine model changed: both drives count as empty until remounted
	input         img_readonly,
	input  [63:0] img_size,
	output [31:0] sd_lba[2],
	output  [1:0] sd_rd,
	output  [1:0] sd_wr,
	input   [1:0] sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[2],
	input         sd_buff_wr,

	input         b_unit2,        // the drive B slot answers as unit 2 (3rd drive) instead of unit 1 (OSD)
	output        busy,           // drive activity (LED)
	output        wait_req,       // a command is running and no byte is ready (MZ-80A interface: CPU WAIT, see below)
	output        present         // the interface is present (MZ-700: its ROM at F000 is on the same card)
);

// Image presence per drive, and write protect from the mount.
reg  [1:0] mounted = 0;
reg  [1:0] wprot = 0;
always @(posedge clk_sys) begin
	integer i;
	for (i = 0; i < 2; i = i + 1)
		if (img_mounted[i]) begin
			mounted[i] <= |img_size;
			wprot[i]   <= img_readonly;
		end
		else if (eject) mounted[i] <= 0;
end

// With no image mounted in Auto mode the interface is absent, so the IPL doesn't stop at
// "Make ready FD".
wire       enable = model_ok & ((mode == 2'd1) | ((mode == 2'd0) & |mounted));
wire       sel    = enable & ~k_mode & (io_addr[7:3] == 5'b11011);   // D8-DF
wire       k_sel  = enable &  k_mode & (io_addr[7:2] == 6'b111110);  // F8-FB (MZ-80FIO)
wire       chip   = sel & ~io_addr[2];                         // D8-DB
wire [1:0] reg_a  = io_addr[1:0];

// Sharp latches.
reg        motor, side, eint;
reg  [1:0] drive;
always @(posedge clk_sys) begin
	reg old_wr;
	old_wr <= io_wr;
	if (reset) begin
		motor <= 0; side <= 0; eint <= 0; drive <= 0;
	end
	else if (io_wr & ~old_wr & sel & io_addr[2]) begin
		case (io_addr[1:0])
			2'd0: begin motor <= io_dout[7]; if (io_dout[2]) drive <= io_dout[1:0]; end
			2'd1: side <= io_dout[0];
			2'd2: ;                                            // density
			2'd3: eint <= io_dout[0];
		endcase
	end
end

// Unit to slot: slot A is unit 0, slot B unit 1, or unit 2 when b_unit2 (MZ-800 CP/M 4.1's HD driver puts its
// 1440K drive C: on unit 2). Other units are absent.
wire       sel_a = (drive == 2'd0);
wire       sel_b = (drive == (b_unit2 ? 2'd2 : 2'd1));

wire [7:0] fdc_dout[2];
wire [1:0] fdc_drq, fdc_busy, fdc_prepare;

// ---------------------------------------------------------------------------------------------------
// MZ-80FIO (k_mode): T3444M registers and the command sequencer.
// ---------------------------------------------------------------------------------------------------
localparam K_READY = 4'h8;                     // status bit 3 (FA bit 7): ready
localparam K_DATA_ERR = 3'd1, K_ID_MISSING = 3'd2, K_LAST_SECTOR = 3'd3, K_CMD_ERR = 3'd6, K_SEEK_ERR = 3'd7;

localparam KS_IDLE = 5'd0,  KS_START = 5'd1,  KS_RESTORE = 5'd2,  KS_SEEK_T = 5'd3,  KS_SEEK_D = 5'd4,
           KS_SEEK_C = 5'd5, KS_WAIT = 5'd6,  KS_SEEK_END = 5'd7, KS_XFER_T = 5'd8,  KS_XFER_S = 5'd9,
           KS_XFER_C = 5'd10, KS_XFER = 5'd11, KS_TND = 5'd12,    KS_FMT_ID = 5'd13, KS_FMT_T = 5'd14,
           KS_FMT_S = 5'd15, KS_FMT_C = 5'd16, KS_FMT_DATA = 5'd17, KS_FMT_NEXT = 5'd18;

reg  [6:0] k_trk, k_sec;
reg        k_side, k_motor, k_tnd;
reg  [1:0] k_drive;
reg  [3:0] k_cmd, k_status;
reg  [7:0] k_data;
reg  [6:0] k_phys[2];                          // head position per drive (the chip's track register for a seek)
reg  [4:0] k_state, k_after;                   // k_after: where KS_WAIT goes when the chip is done
reg  [2:0] op_cnt;                             // a register access to the chip: 3 ce with RD/WR, 3 ce without
reg        op_rd;
reg  [1:0] op_addr;
reg  [7:0] op_din;
reg  [7:0] k_delay;
reg  [6:0] k_fmt_n;                            // Write ID: bytes taken (64 = 16 sectors x C, H, R, N)
reg  [6:0] k_fmt_r[16];
reg  [3:0] k_fmt_i;
reg  [7:0] k_fmt_b;                            // fill bytes written to the current sector
reg        k_fmt_rqm, k_write;

wire       k_unit_ok = ~k_drive[1];            // units 0 and 1: slots A and B
wire       k_d       = k_drive[0];
wire       k_drdy    = k_unit_ok & k_motor & mounted[k_d] & ~fdc_prepare[k_d];
wire       k_rqm     = (k_state == KS_XFER & fdc_drq[k_d]) | k_fmt_rqm;
wire       k_pass    = (k_state == KS_XFER) & k_sel & (io_addr[1:0] == 2'd3);   // FB to the chip's data register
wire [7:0] k_wstat   = fdc_dout[k_d];         // the chip's status while op_addr is 0

always @(posedge clk_sys) begin
	reg old_wr, old_rd;
	old_wr <= io_wr;
	old_rd <= io_rd;

	if (ce_cpu & |op_cnt) op_cnt <= op_cnt - 1'd1;

	if (reset | ~k_mode) begin
		k_state <= KS_IDLE; k_status <= K_READY; k_cmd <= 0;
		k_trk <= 0; k_sec <= 0; k_side <= 0; k_motor <= 0; k_tnd <= 0; k_drive <= 0; k_data <= 0;
		k_phys[0] <= 0; k_phys[1] <= 0; op_cnt <= 0; op_addr <= 0; k_fmt_rqm <= 0;
	end
	else begin
		// CPU side.
		if (io_wr & ~old_wr & k_sel) begin
			case (io_addr[1:0])
				2'd0: {k_side, k_sec} <= io_dout;
				2'd1: k_trk <= io_dout[6:0];
				2'd2: if (k_state == KS_IDLE) begin k_cmd <= io_dout[7:4]; k_status <= 0; k_state <= KS_START; end
				2'd3: begin
					k_data <= io_dout;
					if (k_state == KS_FMT_ID & k_fmt_rqm) begin   // Write ID: C, H, R, N per sector; keep R
						if (k_fmt_n[1:0] == 2'd2) k_fmt_r[k_fmt_n[5:2]] <= io_dout[6:0];
						k_fmt_n   <= k_fmt_n + 1'd1;
						k_fmt_rqm <= 0;
						k_delay   <= 8'd8;
					end
				end
			endcase
		end
		if (io_rd & ~old_rd & k_sel & (io_addr[1:0] == 2'd0)) begin   // IN (C) on F8
			if (io_addr_hi[2]) k_drive <= io_addr_hi[1:0];
			k_motor <= io_addr_hi[3];
			k_tnd   <= io_addr_hi[4];
		end

		// Sequencer. Each chip access sets op_* and op_cnt; a state moves on once op_cnt is back to 0.
		if (~|op_cnt) case (k_state)
			KS_IDLE: ;

			KS_START: begin
				k_write <= k_cmd[3];
				case (k_cmd)
					4'h0: if (~k_drdy) begin k_trk <= 0; k_status <= K_READY; k_state <= KS_IDLE; end     // seek to zero
					      else begin k_trk <= 0; op_addr <= 2'd0; op_din <= 8'h00; op_rd <= 0; op_cnt <= 3'd6;
					                 k_after <= KS_SEEK_END; k_state <= KS_WAIT; end
					4'h1: begin k_status <= K_READY | (k_drdy ? 4'd0 : K_CMD_ERR); if (k_drdy) k_trk <= k_phys[k_d]; k_state <= KS_IDLE; end
					4'h3, 4'h7, 4'hA, 4'hB, 4'hF:                                                            // seek (and ...)
						if (~k_drdy | (k_cmd[3] & wprot[k_d])) begin k_status <= K_READY | K_CMD_ERR; k_state <= KS_IDLE; end
						else if (k_trk > 39) begin k_status <= K_READY | K_SEEK_ERR; k_state <= KS_IDLE; end
						else k_state <= KS_SEEK_T;
					4'h5, 4'h9, 4'hD, 4'h8:                                                                 // read, write, write ID
						if (~k_drdy | (k_cmd[3] & wprot[k_d])) begin k_status <= K_READY | K_CMD_ERR; k_state <= KS_IDLE; end
						else k_state <= (k_cmd == 4'h8) ? KS_FMT_ID : KS_XFER_T;
					default: begin k_status <= K_READY | K_CMD_ERR; k_state <= KS_IDLE; end
				endcase
				k_fmt_n <= 0;
				if (k_cmd == 4'h8) begin k_fmt_rqm <= 0; k_delay <= 8'd8; end
			end

			// Seek: the chip steps from its track register (the head position) to its data register.
			KS_SEEK_T: begin op_addr <= 2'd1; op_din <= {1'b0, k_phys[k_d]}; op_rd <= 0; op_cnt <= 3'd6; k_state <= KS_SEEK_D; end
			KS_SEEK_D: begin op_addr <= 2'd3; op_din <= {1'b0, k_trk};       op_rd <= 0; op_cnt <= 3'd6; k_state <= KS_SEEK_C; end
			KS_SEEK_C: begin op_addr <= 2'd0; op_din <= 8'h10;                op_rd <= 0; op_cnt <= 3'd6;
			                 k_after <= KS_SEEK_END; k_state <= KS_WAIT; end
			KS_WAIT: begin op_addr <= 2'd0; if (~fdc_busy[k_d]) k_state <= k_after; end
			KS_SEEK_END: begin
				k_phys[k_d] <= (k_cmd == 4'h0) ? 7'd0 : k_trk;
				case (k_cmd)
					4'h7, 4'hB, 4'hF: k_state <= KS_XFER_T;
					4'hA:             begin k_state <= KS_FMT_ID; k_fmt_rqm <= 0; k_delay <= 8'd8; end
					default:          begin k_status <= K_READY; k_state <= KS_IDLE; end
				endcase
			end

			// Read or write one sector: the chip's track register is the track the ID must show.
			KS_XFER_T: begin op_addr <= 2'd1; op_din <= {1'b0, k_trk}; op_rd <= 0; op_cnt <= 3'd6; k_state <= KS_XFER_S; end
			KS_XFER_S: begin op_addr <= 2'd2; op_din <= {1'b0, k_sec}; op_rd <= 0; op_cnt <= 3'd6; k_state <= KS_XFER_C; end
			KS_XFER_C: begin op_addr <= 2'd0; op_din <= k_write ? {7'b1010000, k_cmd[2]} : 8'h80; op_rd <= 0; op_cnt <= 3'd6;
			                 k_state <= KS_XFER; end
			KS_XFER: begin
				op_addr <= 2'd0;
				if (~fdc_busy[k_d]) begin
					if (k_wstat[6] & k_write)                  begin k_status <= K_READY | K_CMD_ERR;    k_state <= KS_IDLE; end
					else if (k_wstat[4])                       begin k_status <= K_READY | K_ID_MISSING; k_state <= KS_IDLE; end
					else if (k_wstat[3])                       begin k_status <= K_READY | K_DATA_ERR;   k_state <= KS_IDLE; end
					else begin k_delay <= 8'd200; k_state <= KS_TND; end       // TND is looked at 100 us after the sector
				end
			end
			KS_TND: if (ce_cpu) begin
				if (|k_delay) k_delay <= k_delay - 1'd1;
				else if (k_tnd)          begin k_status <= K_READY;                 k_state <= KS_IDLE; end
				else if (k_sec < 7'd16)  begin k_sec <= k_sec + 1'd1;                 k_state <= KS_XFER_T; end
				else                     begin k_status <= K_READY | K_LAST_SECTOR; k_state <= KS_IDLE; end
			end

			// Write ID (format): take the 16 IDs, then fill each of those sectors with FF.
			KS_FMT_ID: if (ce_cpu) begin
				if (k_fmt_n == 7'd64) begin k_fmt_i <= 0; k_state <= KS_FMT_T; end
				else if (~k_fmt_rqm) begin if (|k_delay) k_delay <= k_delay - 1'd1; else k_fmt_rqm <= 1; end
			end
			KS_FMT_T: begin op_addr <= 2'd1; op_din <= {1'b0, k_phys[k_d]};     op_rd <= 0; op_cnt <= 3'd6; k_state <= KS_FMT_S; end
			KS_FMT_S: begin op_addr <= 2'd2; op_din <= {1'b0, k_fmt_r[k_fmt_i]}; op_rd <= 0; op_cnt <= 3'd6; k_state <= KS_FMT_C; end
			KS_FMT_C: begin op_addr <= 2'd0; op_din <= 8'hA0; op_rd <= 0; op_cnt <= 3'd6; k_fmt_b <= 0; k_state <= KS_FMT_DATA; end
			KS_FMT_DATA:
				if (~fdc_busy[k_d]) k_state <= KS_FMT_NEXT;
				else if (fdc_drq[k_d] & ~k_fmt_b[7]) begin
					op_addr <= 2'd3; op_din <= 8'hFF; op_rd <= 0; op_cnt <= 3'd6; k_fmt_b <= k_fmt_b + 1'd1;
				end
				else op_addr <= 2'd0;
			KS_FMT_NEXT: begin
				op_addr <= 2'd0;
				if (k_fmt_i == 4'd15) begin k_status <= K_READY; k_state <= KS_IDLE; end
				else begin k_fmt_i <= k_fmt_i + 1'd1; k_state <= KS_FMT_T; end
			end
			default: k_state <= KS_IDLE;
		endcase
	end
end

// The sequencer's chip access: RD or WR for the first 3 ce of op_cnt, then 3 ce without.
wire       op_on  = op_cnt[2];
wire       k_io_en_op = |op_cnt;

genvar d;
generate
	for (d = 0; d < 2; d = d + 1) begin : drv
		wire selected = d ? sel_b : sel_a;
		// Commands and reads to the selected drive; track, sector and data writes to both.
		wire k_this = k_unit_ok & (k_d == d);
		wire io_en = k_mode ? k_this & (k_io_en_op | k_pass) : chip & (selected | (io_wr & reg_a != 2'd0));

		wd1793 #(.RWMODE(1), .EDSK(1)) fdc
		(
			.clk_sys(clk_sys),
			.ce(ce_cpu | fdc_prepare[d]),
			.reset(reset),
			.io_en(io_en),
			.rd(k_mode ? (k_pass ? io_rd : op_on &  op_rd) : io_rd),
			.wr(k_mode ? (k_pass ? io_wr : op_on & ~op_rd) : io_wr),
			.addr(k_mode ? (k_pass ? 2'd3 : op_addr) : reg_a),
			.din(k_mode ? (k_pass ? io_dout : op_din) : ~io_dout),     // the MZ-80FIO doesn't invert the bus
			.crc_report(crc_report),
			.dout(fdc_dout[d]),
			.drq(fdc_drq[d]),
			.intrq(),
			.busy(fdc_busy[d]),
			.wp(wprot[d]),
			.fmt_wp(),
			.size_code(3'd2),
			.layout(1'b0),
			.side(k_mode ? k_side : side),
			.ready(mounted[d] & ~fdc_prepare[d]),

			.img_mounted(img_mounted[d]),
			.img_size(img_size[20:0]),
			.img_size_id(img_size[23:0]),
			.disk_index(3'd0),
			.prepare(fdc_prepare[d]),
			.sd_lba(sd_lba[d]),
			.sd_rd(sd_rd[d]),
			.sd_wr(sd_wr[d]),
			.sd_ack(sd_ack[d]),
			.sd_buff_addr(sd_buff_addr),
			.sd_buff_dout(sd_buff_dout),
			.sd_buff_din(sd_buff_din[d]),
			.sd_buff_wr(sd_buff_wr),

			.input_active(1'b0),
			.input_addr(21'd0),
			.input_data(8'd0),
			.input_wr(1'b0),
			.buff_addr(),
			.buff_read(),
			.buff_din(8'd0)
		);
	end
endgenerate

wire       drq_sel = sel_a ? fdc_drq[0] : sel_b ? fdc_drq[1] : 1'b0;
wire       busy_sel = sel_a ? fdc_busy[0] : sel_b ? fdc_busy[1] : 1'b0;

// The MZ-80A interface ROM doesn't poll: its read and write loops run through an opcode fetch at F3FE (F7FE), and the
// interface holds the CPU in WAIT there until the chip has a byte (DRQ) or the command ends (sharpmz.vhd).
assign wait_req = enable & ~k_mode & busy_sel & ~drq_sel;

// A turbo CPU can re-enter the interrupt routine before the chip has dropped DRQ for the byte
// just transferred; hold the interrupt off from the data access until DRQ falls.
reg drq_taken;
always @(posedge clk_sys) begin
	if (reset | ~drq_sel) drq_taken <= 0;
	else if (chip & (reg_a == 2'd3) & (io_rd | io_wr)) drq_taken <= 1;
end

assign io_oe  = k_mode ? k_sel & io_rd & (io_addr[1:0] != 2'd0) : chip & io_rd;     // F8 reads aren't driven
assign io_din = k_mode ? (io_addr[1:0] == 2'd1 ? {5'd0, k_drdy, k_status[3], k_rqm} :
                          io_addr[1:0] == 2'd2 ? {k_status, 4'd0} :
                          k_pass               ? fdc_dout[k_d] : k_data) :
                sel_a ? ~fdc_dout[0] : sel_b ? ~fdc_dout[1] : 8'hFF;
assign int_n  = ~(enable & eint & drq_sel & ~drq_taken);
assign busy   = |(fdc_busy & mounted);
assign present = enable;

`ifdef FDC_IODBG
// Port trace for the sim (make ... -DFDC_IODBG): every read and write of D8-DF, once per access.
reg io_rd_l = 0, io_wr_l = 0;
always @(posedge clk_sys) begin
	io_rd_l <= io_rd; io_wr_l <= io_wr;
	if (io_wr & ~io_wr_l & io_addr[7:3] == 5'b11011) $display("fdcio: OUT %02x <- %02x", io_addr, io_dout);
	if (io_rd_l & ~io_rd & io_addr[7:3] == 5'b11011) $display("fdcio: IN  %02x -> %02x", io_addr, io_din);
end
`endif

endmodule
