//=======================================================================================================
//
// Name:            tape_autotype.sv
// Description:     OSD Auto Load Tape: types the load command for the machine after a tape image is mounted.
//
//                  Armed by a mount, it waits until the first record is in the tape buffer, then WAIT_FRAMES more
//                  frames (counted again from the end of any reset, so a reset after mounting, as MGL files do, is
//                  covered), and types what the model's monitor or IPL wants:
//                      MZ-80K, MZ-80C, MZ-1200 (SP-1002)     LOAD, Return
//                      MZ-80A (SA-1510), MZ-700 (1Z-013A)     L, Return
//                      MZ-800, MZ-1500 (IPL menu)             C
//                      MZ-80B, MZ-2000                        nothing: their IPL loads the tape by itself
//                  Each key is a PS/2 press and release (MiSTer's ps2_key format, set 2 scan codes) put in place of
//                  the keyboard's events, KEY_FRAMES frames each, so the machine sees ordinary key presses. An
//                  even number of events leaves the toggle bit where the keyboard had it.
//
// Copyright:       (C) 2026 The SharpMZ MiSTer contributors. GPL v3 or later.
//
//=======================================================================================================

module tape_autotype
(
	input             clk,
	input             enable,          // OSD Auto Load Tape: On
	input             reset,           // the machine is in reset
	input             vblank,
	input             mounted,         // a tape image was just mounted (pulse)
	input             rec_ready,       // the tape image put a record in the buffer (pulse)
	input       [7:0] rec_no,          // that record's number (0 = the first)
	input       [2:0] model,           // cfg_model
	input             mz1500,

	input      [10:0] ps2_in,          // the keyboard
	output     [10:0] ps2_out          // the keyboard, or the typed keys while typing
);

localparam [7:0] WAIT_FRAMES = 8'd100;     // about 2 s for the monitor or IPL to reach its prompt
localparam [7:0] KEY_FRAMES  = 8'd4;       // each press and each release

// The command, as set 2 scan codes, 0 = end.
function automatic [7:0] cmd(input [2:0] m, input m15, input [2:0] i);
	begin
		cmd = 8'd0;
		if (m <= 3'd2)                                   // LOAD Return
			case (i) 3'd0: cmd = 8'h4B; 3'd1: cmd = 8'h44; 3'd2: cmd = 8'h1C; 3'd3: cmd = 8'h23; 3'd4: cmd = 8'h5A; default: ; endcase
		else if (m == 3'd3 || (m == 3'd4 && !m15))      // L Return
			case (i) 3'd0: cmd = 8'h4B; 3'd1: cmd = 8'h5A; default: ; endcase
		else if (m == 3'd5 || (m == 3'd4 && m15))       // C
			cmd = (i == 3'd0) ? 8'h21 : 8'd0;
	end
endfunction

reg        armed = 0, waiting = 0, typing = 0, released = 0;
reg  [7:0] frames = 0;
reg  [2:0] idx = 0;
reg [10:0] key = 0;
reg        vb_last = 0;
wire       frame = vblank & ~vb_last;
wire [7:0] code = cmd(model, mz1500, idx);

always @(posedge clk) begin
	vb_last <= vblank;
	if (!enable) begin
		armed <= 0; waiting <= 0; typing <= 0;
	end
	else begin
		if (mounted) begin armed <= 1; waiting <= 0; typing <= 0; end
		else if (armed && rec_ready && rec_no == 8'd0) begin
			armed <= 0; waiting <= 1; frames <= 0;
		end

		if (waiting) begin
			if (reset) frames <= 0;
			else if (frame) begin
				if (frames == WAIT_FRAMES) begin
					waiting <= 0;
					if (cmd(model, mz1500, 3'd0) != 8'd0) begin
						typing <= 1; idx <= 0; released <= 1; frames <= KEY_FRAMES;
						key <= ps2_in;
					end
				end
				else frames <= frames + 1'd1;
			end
		end

		if (typing && frame) begin
			if (frames != KEY_FRAMES) frames <= frames + 1'd1;
			else begin
				frames <= 0;
				if (released) begin                                     // next key down, or done
					if (code == 8'd0 || reset) typing <= 0;
					else begin key <= {~key[10], 1'b1, 1'b0, code}; released <= 0; end
				end
				else begin                                              // key up
					key <= {~key[10], 1'b0, 1'b0, code};
					released <= 1;
					idx <= idx + 1'd1;
				end
			end
		end
	end
end

assign ps2_out = typing ? key : ps2_in;

endmodule
