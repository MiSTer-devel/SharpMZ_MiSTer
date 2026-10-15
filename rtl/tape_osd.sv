//=======================================================================================================
//
// Name:            tape_osd.sv
// Description:     Tape image messages over the picture (OSD Tape Messages).
//
//                  For three seconds (150 frames) after the tape image moves, a line at the bottom of the picture says
//                  where the tape is, in the MZ-700's own characters:
//                      TAPE 2/5 EXOLON   89 .PRG     a record is ready to play (number, count, name)
//                      TAPE 6/5 END                  past the last record
//                      TAPE SAVED 6 MYPROG           a save was appended to the image
//                      TAPE FULL                     no room for a save
//                      QD:  1/1 ZULPOKO              an MZ-1500 Quick Disk BASIC file dumped to tape (type 02 at
//                                                    A215): MZ-5Z001 only loads it from a Quick Disk
//                  MiSTer's own popups (CONF_STR "I,") only show fixed strings, so they can't name the program.
//
//                  The text is drawn between the core's video and video_mixer, so it works at 15 kHz and
//                  doubled. Characters are 8x8 (16 pixels wide on 640-pixel lines, the 80-column modes),
//                  white on a black box. A name is Sharp ASCII; the monitor's table turns it into display codes,
//                  which index the character generator (rtl/software/mif/tape_osd_*.hex, tools/make_osd_font.py).
//
// Copyright:       (C) 2026 The SharpMZ MiSTer contributors. GPL v3 or later.
//
//=======================================================================================================

module tape_osd #(
	parameter CLK_HZ    = 70937600,
	parameter FONT_FILE = "rtl/software/mif/tape_osd_font.hex",
	parameter A2D_FILE  = "rtl/software/mif/tape_osd_a2d.hex"
)
(
	input             clk,
	input             ce_pix,
	input             enable,          // OSD Tape Messages: On

	// Video in and out.
	input             hblank,
	input             vblank,
	input       [7:0] r_in, g_in, b_in,
	output      [7:0] r_out, g_out, b_out,

	// What to say: a pulse on show with the message and its details.
	input             show,
	input       [1:0] kind,            // 0 record ready, 1 end of tape, 2 saved, 3 full
	input       [7:0] rec_no,          // 0 = the first record
	input       [7:0] rec_total,
	input     [127:0] name,            // header bytes 1-16 (byte 1 in bits 7:0), ended by 0D
	input             qd_file          // the record is a Quick Disk file (MZ-1500): "QD:" in place of "TAPE"
);

localparam COLS = 32;
localparam [7:0] SHOW_FRAMES = 8'd150;      // about three seconds

// ---- Message text (Sharp ASCII), built when it is shown ---------------------------------------
reg  [7:0] text[COLS];
reg  [7:0] timer = 0;       // frames left to show the message

function automatic [23:0] dec3(input [7:0] v);     // three ASCII digits, leading zeros as spaces (left aligned below)
	reg [7:0] h, t, u;
	begin
		h = v / 8'd100; t = (v / 8'd10) % 8'd10; u = v % 8'd10;
		dec3 = {8'h30 + h, 8'h30 + t, 8'h30 + u};
	end
endfunction

// Put a number at text[p..]: no leading zeros. Returns the next position.
task automatic put_num(input [7:0] v, inout integer p);
	reg [23:0] d;
	begin
		d = dec3(v);
		if (v >= 8'd100) begin text[p] <= d[23:16]; p = p + 1; end
		if (v >= 8'd10)  begin text[p] <= d[15:8];  p = p + 1; end
		text[p] <= d[7:0]; p = p + 1;
	end
endtask

task automatic put_str(input [8*12-1:0] s, input integer n, inout integer p);  // s: n characters, first in the top byte
	integer k;
	begin
		for (k = 0; k < n; k = k + 1) begin
			text[p] <= s[8*(12-1-k) +: 8];
			p = p + 1;
		end
	end
endtask

reg qd_q = 0;               // qd_file, registered (it comes from the OSD status; timing)
always @(posedge clk) qd_q <= qd_file;

integer i, p, e;
always @(posedge clk) begin
	if (show & enable) begin
		for (i = 0; i < COLS; i = i + 1) text[i] <= 8'h20;
		p = 0;
		put_str((qd_q && kind == 2'd0) ? "QD:         " : "TAPE        ", 5, p);   // QD: mount it as the Quick Disk (README)
		case (kind)
			2'd0, 2'd1: begin
				put_num(rec_no + 1'd1, p);
				text[p] <= 8'h2F; p = p + 1;                       // /
				put_num(rec_total, p);
				p = p + 1;
				if (kind == 2'd1) put_str("END         ", 3, p);
			end
			2'd2: begin
				put_str("SAVED       ", 6, p);
				put_num(rec_no + 1'd1, p);
				p = p + 1;
			end
			default: put_str("FULL        ", 4, p);
		endcase
		if (kind == 2'd0 || kind == 2'd2) begin
			e = 0;
			for (i = 0; i < 16; i = i + 1) begin
				if (name[8*i +: 8] == 8'h0D || name[8*i +: 8] == 8'h00) e = 1;
				if (!e && p + i < COLS) text[p + i] <= name[8*i +: 8];
			end
		end
	end
end

// How long it shows: counted in frames, at the start of vertical blanking.
reg vb_t = 0;
always @(posedge clk) begin
	vb_t <= vblank;
	if (!enable)                timer <= 0;
	else if (show)              timer <= SHOW_FRAMES;
	else if (vblank & ~vb_t && timer != 0) timer <= timer - 1'd1;
end

// ---- Raster position ----------------------------------------------------------------------------
reg [10:0] px = 0;          // the pixel the next ce_pix outputs
reg  [9:0] ln = 0;          // active line
reg [10:0] line_w = 320;    // active pixels in the last line
reg  [9:0] frame_h = 200;   // active lines in the last frame
reg        hb_last = 0, vb_last = 0;

always @(posedge clk) if (ce_pix) begin
	hb_last <= hblank;
	vb_last <= vblank;
	if (!hblank) px <= px + 1'd1;
	if (hblank & ~hb_last) begin
		line_w <= px;
		px     <= 0;
		if (!vblank) ln <= ln + 1'd1;
	end
	if (vblank & ~vb_last) begin
		frame_h <= ln;
		ln      <= 0;
	end
end

wire        wide = line_w > 11'd400;                         // 640-pixel lines: double width
wire [10:0] x0   = wide ? 11'd16 : 11'd8;
wire  [9:0] y0   = frame_h - 10'd14;
wire [10:0] dx   = px - x0;
wire  [9:0] dy   = ln - y0;
wire  [5:0] col  = wide ? dx[9:4] : dx[8:3];
wire  [2:0] bit_ = wide ? dx[3:1] : dx[2:0];
wire        in_text = px >= x0 && col < COLS && ln >= y0 && dy < 10'd8;
wire        in_box  = timer != 0 && px + 11'd4 >= x0 && px < x0 + (wide ? 11'd16 : 11'd8) * COLS + 11'd4 &&
                      ln + 10'd2 >= y0 && ln < y0 + 10'd10;

// ---- Character lookup: Sharp ASCII -> display code -> glyph row (two clocks; ce_pix is at most every fourth) ----
reg [7:0] a2d[256];
reg [7:0] font[2048];
initial begin
	$readmemh(A2D_FILE, a2d);
	$readmemh(FONT_FILE, font);
end
reg [7:0] code_q, glyph_q;
reg [2:0] row_q;
always @(posedge clk) begin
	code_q  <= a2d[text[col[4:0]]];
	row_q   <= dy[2:0];
	glyph_q <= font[{code_q, row_q}];
end

// ---- Output: the picture passes straight through (no delay against its sync); the box replaces it ----
wire [7:0] ink = (in_text && glyph_q[3'd7 - bit_]) ? 8'hFF : 8'h00;
assign r_out = in_box ? ink : r_in;
assign g_out = in_box ? ink : g_in;
assign b_out = in_box ? ink : b_in;

endmodule
