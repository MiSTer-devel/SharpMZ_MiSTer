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
//  Copyright (C) 2026 SharpMZ MiSTer contributors. GPL v2 or later.
//
//============================================================================

module mz_fdc
(
	input         clk_sys,
	input         reset,
	input         ce_cpu,         // CPU clock enable; the controller timing runs at CPU speed
	input         model_ok,       // Model has the interface (MZ-700/800, MZ-80B/2000)
	input   [1:0] mode,           // 0 Auto (present while a disk image is mounted), 1 On, 2 Off
	input         crc_report,     // Report sectors dumped with a CRC error (else read them as good)

	// Z80 I/O
	input   [7:0] io_addr,
	input         io_rd,
	input         io_wr,
	input   [7:0] io_dout,        // CPU data out
	output  [7:0] io_din,         // data for the CPU
	output        io_oe,          // this device answers the current read
	output        int_n,

	// MiSTer image slots, one per drive
	input   [1:0] img_mounted,
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
end

// With no image mounted in Auto mode the interface is absent, so the IPL doesn't stop at
// "Make ready FD".
wire       enable = model_ok & ((mode == 2'd1) | ((mode == 2'd0) & |mounted));
wire       sel    = enable & (io_addr[7:3] == 5'b11011);       // D8-DF
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

genvar d;
generate
	for (d = 0; d < 2; d = d + 1) begin : drv
		wire selected = d ? sel_b : sel_a;
		// Commands and reads to the selected drive; track, sector and data writes to both.
		wire io_en = chip & (selected | (io_wr & reg_a != 2'd0));

		wd1793 #(.RWMODE(1), .EDSK(1)) fdc
		(
			.clk_sys(clk_sys),
			.ce(ce_cpu | fdc_prepare[d]),
			.reset(reset),
			.io_en(io_en),
			.rd(io_rd),
			.wr(io_wr),
			.addr(reg_a),
			.din(~io_dout),
			.crc_report(crc_report),
			.dout(fdc_dout[d]),
			.drq(fdc_drq[d]),
			.intrq(),
			.busy(fdc_busy[d]),
			.wp(wprot[d]),
			.fmt_wp(),
			.size_code(3'd2),
			.layout(1'b0),
			.side(side),
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

// A turbo CPU can re-enter the interrupt routine before the chip has dropped DRQ for the byte
// just transferred; hold the interrupt off from the data access until DRQ falls.
reg drq_taken;
always @(posedge clk_sys) begin
	if (reset | ~drq_sel) drq_taken <= 0;
	else if (chip & (reg_a == 2'd3) & (io_rd | io_wr)) drq_taken <= 1;
end

assign io_oe  = chip & io_rd;
assign io_din = sel_a ? ~fdc_dout[0] : sel_b ? ~fdc_dout[1] : 8'hFF;
assign int_n  = ~(enable & eint & drq_sel & ~drq_taken);
assign busy   = |(fdc_busy & mounted);
assign present = enable;

endmodule
