//============================================================================
//
//  MZ-800 border (OSD Display > MZ-800 Border).
//
//  The core outputs only the 320x200 / 640x200 picture. The MZ-800 draws its border colour (GDG register
//  BCOL, OUT (CF) with B = 06, IGRB) around it: in 640-mode pixels 154 on the left, 134 on the right, 46
//  lines above and 42 below (mz800emu's mz800_video.h; half the widths in 320 mode). All of that lies in
//  the blanking time of the 568 (1136) x 312 frame, clear of sync, so the border is added here, after the
//  video controller and before video_mixer: the blanking is opened over the border area and filled with the
//  border colour. The picture itself, its timing and the frame tests are unchanged.
//
//  Copyright (C) 2026 SharpMZ MiSTer contributors. GPL v2 or later.
//
//============================================================================

module mz800_border
(
	input        clk,
	input        ce_pix,
	input        enable,          // MZ-800 with the OSD option on
	input        hblank,
	input        vblank,
	input  [3:0] bcol,            // I, G, R, B
	input  [7:0] r_in, g_in, b_in,
	output [7:0] r_out, g_out, b_out,
	output       hblank_out,      // the blanking with the border area opened (to video_mixer)
	output       vblank_out
);

// MZ-800 16 colours, 4-bit levels (VideoController.vhd PALETTE_LUT, mz800emu's colours).
wire [3:0] pal_r[16] = '{4'h0, 4'h4, 4'hD, 4'hB, 4'h4, 4'h2, 4'hE, 4'hD, 4'h8, 4'h0, 4'hF, 4'hF, 4'h5, 4'h8, 4'hF, 4'hF};
wire [3:0] pal_g[16] = '{4'h0, 4'h4, 4'h3, 4'h0, 4'h6, 4'hC, 4'hD, 4'hD, 4'h8, 4'h8, 4'h0, 4'h5, 4'hF, 4'hF, 4'hF, 4'hF};
wire [3:0] pal_b[16] = '{4'h0, 4'hA, 4'h0, 4'h8, 4'h0, 4'hF, 4'h3, 4'hD, 4'h8, 4'hE, 4'h0, 4'hC, 4'h5, 4'hF, 4'h2, 4'hF};

reg        hb_l = 1;
reg [11:0] hc = 0;                // pixel in the line, from the first picture pixel
reg [11:0] wid = 320;             // picture width (the hblank falling to rising distance)
reg [11:0] len = 568;             // pixels per line
reg  [9:0] vc = 0;                // line, from the first picture line
reg  [9:0] vtot = 312;            // lines per frame
reg        vb_line = 1;           // vblank at the start of the previous line

always @(posedge clk) if (ce_pix) begin
	hb_l <= hblank;
	hc   <= hc + 1'd1;
	if (~hb_l & hblank) wid <= hc;
	if (hb_l & ~hblank) begin                         // a line starts
		len     <= hc;
		hc      <= 12'd1;
		vb_line <= vblank;
		if (vb_line & ~vblank) begin vtot <= vc; vc <= 0; end
		else vc <= vc + 1'd1;
	end
end

// The left border is drawn at the end of the line before, so it is placed by the NEXT line's number: each
// line's border, picture and border are then one run of DE (the framework sizes the frame from the first run).
wire        wide = wid > 12'd400;
wire [11:0] bl   = wide ? 12'd154 : 12'd77;
wire [11:0] br   = wide ? 12'd134 : 12'd67;
wire  [9:0] vn   = (vc >= vtot) ? 10'd0 : vc + 1'd1;
wire        v_in_cur  = (vc < 10'd242) | (vc > vtot - 10'd46);
wire        v_in_next = (vn < 10'd242) | (vn > vtot - 10'd46);
wire        in_h_head = hc < wid + br;
wire        in_h_tail = hc >= len - bl;
wire        in_hv = (in_h_head & v_in_cur) | (in_h_tail & v_in_next);
wire        pic  = ~hblank & ~vblank;
wire        brd  = enable & ~pic & in_hv;

// Horizontally the border is open on every line; vertically by the line it belongs to (the next one for the
// left border), so ~(hblank_out | vblank_out) is exactly pic | brd.
assign hblank_out = hblank & ~(enable & (in_h_head | in_h_tail));
assign vblank_out = vblank & ~(enable & ((in_h_head & v_in_cur) | (in_h_tail & v_in_next)));
assign r_out = pic ? r_in : brd ? {2{pal_r[bcol]}} : 8'd0;
assign g_out = pic ? g_in : brd ? {2{pal_g[bcol]}} : 8'd0;
assign b_out = pic ? b_in : brd ? {2{pal_b[bcol]}} : 8'd0;

endmodule
