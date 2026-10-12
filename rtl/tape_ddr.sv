//============================================================================
//
//  The CMT's 64 KB tape data buffer in the DE10-Nano's DDR3 (MiSTer DDRAM port) instead of block RAM.
//
//  Two byte ports share it:
//    A - the CMT (cmt.vhd): it plays the buffer out bit by bit and records into it, a byte every few
//        hundred microseconds at the most. a_ready says a_dout is the byte at a_addr; the transmitter waits
//        for it. Writes are taken on the rising edge of a_we.
//    B - the host side: Main's Load Tape to CMT download, tape_image.sv loading a record and reading a saved
//        one back. b_we is a one-clock write strobe, b_rd asks for the byte at b_addr; b_busy holds the host
//        (ioctl_wait, tape_image's bus wait) while a write is pending or a read is not ready.
//
//  Each port keeps one 8-byte line (the DDR3 word) as a read cache. Writes go through to DDR3 (one byte
//  lane) and update any cached copy at once, so a read after a write never sees old data.
//
//  The buffer is at byte 0x30000000 of DDR3, the region MiSTer leaves to cores.
//
//  Copyright (C) 2026 SharpMZ MiSTer contributors. GPL v2 or later.
//
//============================================================================

module tape_ddr
(
	input             clk,
	input             reset,

	input      [15:0] a_addr,
	input             a_we,
	input       [7:0] a_din,
	output      [7:0] a_dout,
	output            a_ready,

	input      [15:0] b_addr,
	input             b_we,
	input             b_rd,
	input       [7:0] b_din,
	output      [7:0] b_dout,
	output            b_busy,

	output            DDRAM_CLK,
	input             DDRAM_BUSY,
	output      [7:0] DDRAM_BURSTCNT,
	output reg [28:0] DDRAM_ADDR,
	input      [63:0] DDRAM_DOUT,
	input             DDRAM_DOUT_READY,
	output reg        DDRAM_RD,
	output reg [63:0] DDRAM_DIN,
	output reg  [7:0] DDRAM_BE,
	output reg        DDRAM_WE
);

assign DDRAM_CLK      = clk;
assign DDRAM_BURSTCNT = 8'd1;

wire [28:0] base = 29'h06000000;                   // byte 0x30000000 / 8

// Read caches.
reg  [63:0] line_a, line_b;
reg  [12:0] tag_a, tag_b;
reg         val_a = 0, val_b = 0;
assign a_dout  = line_a[{a_addr[2:0], 3'b000} +: 8];
assign b_dout  = line_b[{b_addr[2:0], 3'b000} +: 8];
wire   hit_a   = val_a & (tag_a == a_addr[15:3]);
wire   hit_b   = val_b & (tag_b == b_addr[15:3]);

// Pending writes.
reg         wa_pend = 0, wb_pend = 0;
reg  [15:0] wa_addr, wb_addr;
reg   [7:0] wa_data, wb_data;
reg         a_we_l = 0;

assign a_ready = hit_a & ~wa_pend;
assign b_busy  = wb_pend | (b_rd & ~hit_b);

localparam S_IDLE = 0, S_WR = 1, S_RD = 2, S_RDATA = 3;
reg  [1:0] state = S_IDLE;
reg        rd_for_b;                                // the fill in flight is for port B
reg [12:0] rd_tag;
reg        wr_is_b;

// Update a cached line with a written byte.
function automatic [63:0] put(input [63:0] line, input [2:0] lane, input [7:0] v);
	put = line;
	put[{lane, 3'b000} +: 8] = v;
endfunction

always @(posedge clk) begin
	a_we_l <= a_we;
	if (reset) begin
		state <= S_IDLE; DDRAM_RD <= 0; DDRAM_WE <= 0;
		wa_pend <= 0; wb_pend <= 0; val_a <= 0; val_b <= 0;
	end
	else begin
		// Take writes; the caches see them at once.
		if (a_we & ~a_we_l) begin
			wa_pend <= 1; wa_addr <= a_addr; wa_data <= a_din;
			if (val_a && tag_a == a_addr[15:3]) line_a <= put(line_a, a_addr[2:0], a_din);
			if (val_b && tag_b == a_addr[15:3]) line_b <= put(line_b, a_addr[2:0], a_din);
		end
		if (b_we & ~wb_pend) begin
			wb_pend <= 1; wb_addr <= b_addr; wb_data <= b_din;
			if (val_a && tag_a == b_addr[15:3]) line_a <= put(line_a, b_addr[2:0], b_din);
			if (val_b && tag_b == b_addr[15:3]) line_b <= put(line_b, b_addr[2:0], b_din);
		end
		if ((a_we & ~a_we_l) & (b_we & ~wb_pend)) begin   // both in one clock: drop the lines, read them again
			val_a <= 0; val_b <= 0;
		end

		case (state)
		S_IDLE:
			if (wb_pend | wa_pend) begin
				wr_is_b    <= wb_pend;
				DDRAM_ADDR <= base + (wb_pend ? wb_addr[15:3] : wa_addr[15:3]);
				DDRAM_DIN  <= {8{wb_pend ? wb_data : wa_data}};
				DDRAM_BE   <= 8'd1 << (wb_pend ? wb_addr[2:0] : wa_addr[2:0]);
				DDRAM_WE   <= 1;
				state      <= S_WR;
			end
			else if (b_rd & ~hit_b) begin
				rd_for_b <= 1; rd_tag <= b_addr[15:3];
				DDRAM_ADDR <= base + b_addr[15:3]; DDRAM_RD <= 1; state <= S_RD;
			end
			else if (~hit_a) begin
				rd_for_b <= 0; rd_tag <= a_addr[15:3];
				DDRAM_ADDR <= base + a_addr[15:3]; DDRAM_RD <= 1; state <= S_RD;
			end
		S_WR:
			if (~DDRAM_BUSY) begin
				DDRAM_WE <= 0;
				if (wr_is_b) wb_pend <= 0; else wa_pend <= 0;
				state <= S_IDLE;
			end
		S_RD:
			if (~DDRAM_BUSY) begin DDRAM_RD <= 0; state <= S_RDATA; end
		S_RDATA:
			if (DDRAM_DOUT_READY) begin
				// A write to this line while the read was in flight is already in DDR3 or still pending;
				// the line is dropped in that case and read again.
				if (rd_for_b) begin line_b <= DDRAM_DOUT; tag_b <= rd_tag; val_b <= ~(wa_pend | wb_pend); end
				else          begin line_a <= DDRAM_DOUT; tag_a <= rd_tag; val_a <= ~(wa_pend | wb_pend); end
				state <= S_IDLE;
			end
		endcase
	end
end

endmodule
