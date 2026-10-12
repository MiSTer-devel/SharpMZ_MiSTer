//============================================================================
//
//  Sharp MZ-1500 / MZ-800 Quick Disk (MZ-1F11 drive behind a Z80 SIO at F4-F7).
//
//  The SIO is modelled at byte level, after mz800emu's hw-generic/qdisk (qdisk.c):
//    F4 data A  - bytes from the drive (sequential read of the disk stream)
//    F5 data B  - reads FF
//    F6 ctrl A  - RR0: b0 byte available, b2 Tx buffer empty, b3 DCD (disk present),
//                 b4 hunt (sync search in progress), b5 CTS (not write protected); RR1 b6 CRC error
//    F7 ctrl B  - WR5 b7 is the drive motor; turning it off rewinds the head (head home).
//                 RR0 reads FF, as mz800emu (its head-home bit is never returned).
//  The disk turns: while the motor runs a byte passes the head every BYTE_CLKS clocks (about 79 us, so
//  a 48 KB file loads in about 4 s as on the real drive), whether the CPU reads it or not. A WR3 write
//  with b0 (Rx enable) and b4 (enter hunt) watches the passing bytes for WR6, WR7; with b1 (sync load
//  inhibit) further sync characters are dropped, then each byte goes to the receive buffer (RR0 b0) and
//  a data read takes it. mz800emu instead advances the disk only when the CPU reads, which works for its
//  cleaned-up .mzq images but not for real dumps: after each block they carry trailing sync bytes and a
//  gap that the drive spins past while the BIOS handles the block.
//
//  The disk is the raw byte stream of the medium: a .mzq (mz800emu) or a .qdf (16-byte "-QD format-"
//  header, skipped), read through two 512-byte sector buffers with prefetch. If a sector is late the
//  disk waits for it.
//
//  Writing follows the Z80 SIO in bisync mode as the MZ-1500 ROM drives it (FD4D-FDD9): WR5 b1 (RTS) is
//  the write gate. With it and Tx enable (b3) on, every byte time the transmitter puts one byte on the disk:
//  00 while WR5 b4 (break) is set, else the Tx buffer (F4), else on an underrun the CRC-16 of the bytes
//  since the last Tx CRC reset (once per WR0 "reset Tx underrun/EOM latch", and only after a data byte:
//  the ROM resets the latch just before it writes A5), else sync characters (WR6, WR7). This gives the layout of the real dumps: 00 run, 16 x9, A5, data, CRC (0xA001 reflected, low byte
//  first), 16 ... Written sectors go back to the image when the head leaves them or the motor stops.
//
//  Copyright (C) 2026 SharpMZ MiSTer contributors. GPL v2 or later.
//
//============================================================================

module mz_qdisk
(
	input         clk_sys,
	input         reset,
	input         enable,         // The machine has the drive (MZ-1500; MZ-800 with an image mounted)

	// Z80 I/O
	input   [7:0] io_addr,
	input         io_rd,
	input         io_wr,
	input   [7:0] io_dout,        // CPU data out
	output  [7:0] io_din,
	output        io_oe,

	// MiSTer image slot
	input         img_mounted,
	input         img_readonly,
	input  [63:0] img_size,
	output reg [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	output        busy            // motor on (LED)
);

localparam [16:0] QD_MAX    = 17'd89826;         // mz800emu QDISK_IMAGE_MAX_SIZE
parameter         BYTE_CLKS = 5583;              // clk_sys clocks per byte (70.9 MHz, ~101.6 kbit/s; sim.v scales it)

wire sel   = enable & (io_addr[7:2] == 6'b111101); // F4-F7
assign io_oe = sel & io_rd;

// ---------------------------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------------------------
reg        mounted = 0;
reg        wprot   = 1;                          // image is read only
reg [19:0] size    = 0;                          // image size (bytes)
reg  [4:0] base    = 0;                          // 16 for a .qdf
reg        base_known = 0;

// Two sector buffers, selected by the sector number's bit 0. Port A is the SD side, port B the head.
wire [7:0] buf_q;
reg  [9:0] buf_raddr;
reg        hd_we = 0;                            // head writes a byte
reg  [9:0] hd_addr;
reg  [7:0] hd_data;

wd1793_mem #(.DATAWIDTH(8), .ADDRWIDTH(10)) qbuf
(
	.clock(clk_sys),
	.address_a({sd_lba[0], sd_buff_addr}), .data_a(sd_buff_dout), .wren_a(sd_ack & sd_buff_wr), .q_a(sd_buff_din),
	.address_b(hd_we ? hd_addr : buf_raddr), .data_b(hd_data), .wren_b(hd_we), .q_b(buf_q)
);

reg  [1:0] valid = 0;
reg  [1:0] dirty = 0;                            // written by the head, not yet back in the image
reg [10:0] tag[2];                               // sector number held by each buffer

// ---------------------------------------------------------------------------------------------
// SIO state
// ---------------------------------------------------------------------------------------------
reg  [7:0] wa[8], wb[8];                         // write registers, channel A / B
reg  [2:0] pa, pb;                               // register pointers
reg  [7:0] rb2;                                  // channel B interrupt vector (RR2)
reg        hunt = 0;                             // RR0 b4, channel A
reg        head_home = 1;
reg [16:0] pos = 0;                              // position in the disk stream (after the header)

wire       motor = wb[5][7];
assign busy = mounted & motor;

// The byte at pos: absolute offset, sector, buffer.
wire [19:0] abs     = {3'd0, pos} + base;
wire [10:0] sector  = abs[19:9];
wire        b_sel   = sector[0];
wire        in_img  = abs < size;
wire        hit     = valid[b_sel] & (tag[b_sel] == sector);

reg  [7:0] head_byte;                            // byte at pos, once fetched
reg        head_ok = 0;                          // head_byte is current
reg  [1:0] fetch = 0;
reg [16:0] head_pos;

// The byte under the head (FF past the end of the image or the medium).
wire [7:0] next_byte = (in_img & (pos <= QD_MAX)) ? head_byte : 8'hFF;
wire       spinning  = mounted & motor & base_known;

reg  [7:0] rx_buf;
reg        rx_avail = 0;                         // RR0 b0
reg        overrun  = 0;                         // RR1 b5
reg        strip    = 0;                         // dropping sync characters after hunt (WR3 b1)
reg [12:0] tick     = 0;

// Transmitter
reg  [7:0] tx_buf;
reg        tx_full  = 0;                         // RR0 b2 is its inverse
reg        eom      = 1;                         // Tx underrun/EOM latch: set = an underrun sends sync, not CRC
reg        crc_hi   = 0;                         // sending the CRC's second byte
reg        crc_arm  = 0;                         // a data byte went out since the Tx CRC reset
reg        sync_hi  = 0;                         // next sync character is WR7
reg [15:0] crc      = 0;

function [15:0] crc16(input [15:0] c, input [7:0] d);   // CRC-16, x16+x15+x2+1, LSB first
	integer i;
	reg [15:0] x;
	begin
		x = c ^ {8'h00, d};
		for (i = 0; i < 8; i = i + 1) x = x[0] ? ((x >> 1) ^ 16'hA001) : (x >> 1);
		crc16 = x;
	end
endfunction

wire       wgate  = wa[5][3] & wa[5][1] & ~wprot;    // Tx enabled with RTS: the drive writes
wire [7:0] tx_out = wa[5][4] ? 8'h00 :
                    tx_full  ? tx_buf :
                    (~eom & crc_arm) ? (crc_hi ? crc[15:8] : crc[7:0]) :
                    sync_hi  ? wa[7] : wa[6];

wire [7:0] rr0_a = {1'b0, eom, ~wprot /* CTS */, hunt, mounted, ~tx_full, 1'b0, rx_avail};
wire [7:0] rr1_a = {1'b0, pos > QD_MAX, overrun, 5'd0};

// ---------------------------------------------------------------------------------------------
// CPU access and the turning disk
// ---------------------------------------------------------------------------------------------
reg        rd_last = 0, wr_last = 0;
reg  [7:0] rd_data;
assign io_din = rd_data;

reg [7:0] last_b;                                // hunt: previous byte
reg       consume;                               // the head moved on to the next byte

always @(posedge clk_sys) begin
	rd_last <= io_rd & sel;
	wr_last <= io_wr & sel;
	consume <= 0;
	hd_we   <= 0;

	// --- the disk: one byte every BYTE_CLKS while the motor runs (waits for a late sector) ---
	if (~spinning) tick <= BYTE_CLKS[12:0];
	else if (tick != 0) tick <= tick - 1'd1;
	else if ((head_ok | ~in_img | (pos > QD_MAX)) & ~consume) begin
		tick    <= BYTE_CLKS[12:0];
		consume <= 1;
		if (wgate) begin
			if (in_img & (pos <= QD_MAX)) begin
				hd_we   <= 1;
				hd_addr <= {b_sel, abs[8:0]};
				hd_data <= tx_out;
				dirty[b_sel] <= 1;
			end
			if (wa[5][4]) begin end                              // break
			else if (tx_full) begin
				tx_full <= 0;
				crc_arm <= 1;
				if (wa[5][0]) crc <= crc16(crc, tx_buf);
			end
			else if (~eom & crc_arm) begin
				crc_hi <= ~crc_hi;
				if (crc_hi) begin eom <= 1; crc_arm <= 0; end
			end
			else sync_hi <= ~sync_hi;
		end
		else if (hunt) begin
			last_b <= next_byte;
			if (last_b == wa[6] && next_byte == wa[7]) begin hunt <= 0; strip <= wa[3][1]; end
		end
		else if (wa[3][0]) begin                                // Rx enabled
			if (strip && (next_byte == wa[6] || next_byte == wa[7])) begin end
			else begin
				strip   <= 0;
				rx_buf  <= next_byte;
				if (rx_avail) overrun <= 1;
				rx_avail <= 1;
			end
		end
	end

	// --- reads (on the first clock of the cycle) ---
	if (io_rd & sel & ~rd_last) begin
		case (io_addr[1:0])
			2'd0: begin                                     // data A
				head_home <= 0;
				rd_data   <= rx_avail ? rx_buf : 8'hFF;
				rx_avail  <= 0;
			end
			2'd1: rd_data <= 8'hFF;                         // data B
			2'd2: begin                                     // ctrl A
				case (pa[1:0])
					2'd0: rd_data <= rr0_a;
					2'd1: rd_data <= rr1_a;
					default: rd_data <= 8'h00;
				endcase
				pa <= 0;
			end
			2'd3: begin                                     // ctrl B
				rd_data <= (pb == 0) ? 8'hFF : (pb[1:0] == 2'd2) ? rb2 : 8'h00;
				pb <= 0;
			end
		endcase
	end

	// --- writes ---
	if (io_wr & sel & ~wr_last) begin
		if (io_addr[1]) begin                               // control
			if (~io_addr[0]) begin                          // channel A
				wa[pa] <= io_dout;
				if (pa == 0) begin
					pa <= io_dout[2:0];
					if (io_dout[5:3] == 3'd3) begin wa[1] <= 0; wa[2] <= 0; wa[3] <= 0; wa[4] <= 0; wa[5] <= 0; wa[6] <= 0; wa[7] <= 0; hunt <= 0; rx_avail <= 0; tx_full <= 0; eom <= 1; end
					if (io_dout[5:3] == 3'd6) overrun <= 0;     // error reset
					if (io_dout[7:6] == 2'd2) begin crc <= 0; crc_arm <= 0; end   // reset Tx CRC generator
					if (io_dout[7:6] == 2'd3) begin eom <= 0; crc_hi <= 0; end   // reset Tx underrun/EOM latch
				end
				else begin
					if (pa == 3 && io_dout[4] && io_dout[0]) begin hunt <= 1; last_b <= 8'h00; rx_avail <= 0; end
					pa <= 0;
				end
			end
			else begin                                      // channel B
				wb[pb] <= io_dout;
				if (pb == 0) begin
					pb <= io_dout[2:0];
					if (io_dout[5:3] == 3'd3) begin wb[1] <= 0; wb[2] <= 0; wb[3] <= 0; wb[4] <= 0; wb[5] <= 0; wb[6] <= 0; wb[7] <= 0; end
				end
				else begin
					if (pb == 2) rb2 <= io_dout;
					if (pb == 5 && ~io_dout[7]) begin pos <= 0; head_home <= 1; hunt <= 0; rx_avail <= 0; end   // motor off: rewind
					pb <= 0;
				end
			end
		end
		else if (~io_addr[0]) begin tx_buf <= io_dout; tx_full <= 1; end   // data A
	end

	if (consume) pos <= pos + 1'd1;

	if (reset) begin
		wa[0] <= 0; wa[1] <= 0; wa[2] <= 0; wa[3] <= 0; wa[4] <= 0; wa[5] <= 0; wa[6] <= 0; wa[7] <= 0;
		wb[0] <= 0; wb[1] <= 0; wb[2] <= 0; wb[3] <= 0; wb[4] <= 0; wb[5] <= 0; wb[6] <= 0; wb[7] <= 0;
		pa <= 0; pb <= 0; hunt <= 0; pos <= 0; head_home <= 1; rx_avail <= 0; overrun <= 0;
		tx_full <= 0; eom <= 1; crc <= 0;
	end
	if (img_mounted) begin pos <= 0; head_home <= 1; hunt <= 0; rx_avail <= 0; dirty <= 0; end
	if (wb_clear) dirty[wb_buf] <= 0;
end

// ---------------------------------------------------------------------------------------------
// Fetch the byte at pos from the buffers (2 clocks); invalidate when pos moves.
// ---------------------------------------------------------------------------------------------
always @(posedge clk_sys) begin
	if (consume | img_mounted | reset | (head_pos != pos)) begin
		head_ok <= 0;
		fetch   <= 0;
	end
	else if (~head_ok & hit) begin
		case (fetch)
			2'd0: begin buf_raddr <= {b_sel, abs[8:0]}; fetch <= 2'd1; end
			2'd1: fetch <= 2'd2;
			2'd2: begin head_byte <= buf_q; head_ok <= 1; fetch <= 0; end
		endcase
	end
	head_pos <= pos;
end

// ---------------------------------------------------------------------------------------------
// Sector loading: keep the current sector and the next one in the buffers while the motor runs.
// Sector 0 is read at mount to see whether there is a .qdf header. A written buffer goes back to the
// image first, once the head has left its sector or the motor has stopped.
// ---------------------------------------------------------------------------------------------
reg  [2:0] ld_state = 0;
reg [10:0] ld_sector;
reg        wb_clear = 0;                         // to the SIO block: the write-back took this buffer
reg        wb_buf;
wire       wb0 = dirty[0] & (~motor | tag[0] != sector);
wire       wb1 = dirty[1] & (~motor | tag[1] != sector);

wire [10:0] want0 = base_known ? sector : 11'd0;
wire [10:0] want1 = sector + 1'd1;
wire        need0 = ~(valid[want0[0]] & tag[want0[0]] == want0);
wire        need1 = base_known & ({want1, 9'd0} < size) & ~(valid[want1[0]] & tag[want1[0]] == want1);

reg  [1:0] hdr_cnt;
reg [23:0] hdr;

always @(posedge clk_sys) begin
	wb_clear <= 0;
	case (ld_state)
		3'd0: if (mounted & (wb0 | wb1)) begin              // write back
			wb_buf   <= ~wb0;
			wb_clear <= 1;
			sd_lba   <= {21'd0, wb0 ? tag[0] : tag[1]};
			sd_wr    <= 1;
			ld_state <= 3'd4;
		end
		else if (mounted & (motor | ~base_known)) begin
			if (need0) begin ld_sector <= want0; ld_state <= 3'd1; end
			else if (need1 & motor) begin ld_sector <= want1; ld_state <= 3'd1; end
		end
		3'd1: begin
			sd_lba <= {21'd0, ld_sector};
			valid[ld_sector[0]] <= 0;
			sd_rd <= 1;
			ld_state <= 3'd2;
		end
		3'd2: if (sd_ack) begin sd_rd <= 0; ld_state <= 3'd3; end
		3'd3: if (~sd_ack) begin
			valid[ld_sector[0]] <= 1;
			tag[ld_sector[0]]   <= ld_sector;
			ld_state <= 3'd0;
		end
		3'd4: if (sd_ack) begin sd_wr <= 0; ld_state <= 3'd5; end
		3'd5: if (~sd_ack) ld_state <= 3'd0;
		default: ld_state <= 3'd0;
	endcase

	// Header check on the first bytes of sector 0 as they arrive.
	if (sd_ack & sd_buff_wr & ~base_known & ld_sector == 0 && sd_buff_addr < 3) begin
		hdr <= {hdr[15:0], sd_buff_dout};
		if (sd_buff_addr == 2) begin
			base       <= ({hdr[15:0], sd_buff_dout} == 24'h2D5144) ? 5'd16 : 5'd0;   // "-QD"
			base_known <= 1;
		end
	end

	if (img_mounted) begin
		mounted    <= |img_size;
		wprot      <= img_readonly;
		size       <= |img_size[63:20] ? 20'hFFFFF : img_size[19:0];
		valid      <= 0;
		base_known <= 0;
		base       <= 0;
		ld_state   <= 0;
		sd_rd      <= 0;
		sd_wr      <= 0;
	end
end

endmodule
