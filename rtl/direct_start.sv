//============================================================================
//
//  Load Direct starts the program (MZ-80K/C/1200/80A, MZ-700, MZ-800, MZ-1500).
//
//  A direct load (OSD "Load Tape to RAM") writes the MZF header to 10F0 and the body to its load address
//  while the machine is held in a warm reset. Before, the machine then just booted and the user typed J.
//  On the MZ-800 that boot (IPL and monitor) uses 10F0-11FF, so programs that start or keep data there
//  (Exploding Fist, Jumpin' Jack, Solomon's Key, ...) were broken, and in MZ-800 mode the CG ROM sits at
//  1000-1FFF.
//
//  Now, as mz800emu's bootstrap does, a machine-code program (MZF type 01) is started; other types (BASIC
//  programs, data) only reset, as before:
//    1. The bytes the load puts in 10F0-11FF are kept here (272 bytes, with a written flag each).
//    2. The machine boots normally for WAIT_CLKS (about 1.5 s): the ROM sets up the 8255, 8253, PIO,
//       video and its own work area, as a real cold start.
//    3. Those bytes are written back through the core download bus.
//    4. From the first opcode fetch after the next start of vertical blanking, the CPU's memory reads are fed a
//       short program:
//         NOP, DI,
//         MZ-800 (either mode): IN A,(E1) (CG ROM and VRAM out: 1000-1FFF and 8000-BFFF DRAM),
//                               OUT (E3),A (ROM at E000), as mz800emu's start leaves the map,
//         then, where the E0-E4 ports exist: OUT (E0),A if it loads below 1000 (0000-0FFF DRAM),
//         LD SP,10F0, JP exec.
//       Planetoids clears 8000-9FFF expecting DRAM there; with VRAM still mapped the screen stayed black.
//  The leading NOP absorbs the case of the first injected fetch completing a CB/ED/DD/FD prefix.
//
//  Copyright (C) 2026 SharpMZ MiSTer contributors. GPL v2 or later.
//
//============================================================================

module direct_start #(parameter CLK_HZ = 70937600)
(
	input             clk,
	input             reset,
	input             enable,          // model supports it (not MZ-80B/2000) and the OSD option is on
	input             is_mz800,        // MZ-800 (either position of the rear switch)
	input             has_e0,          // the E0-E4 bank ports exist (MZ-700/800/1500)
	input             vblank,          // the program starts at the start of vertical blanking

	// The core download bus as the direct load drives it.
	input             dl_active,       // a direct load is in progress
	input             dl_wr,
	input      [24:0] dl_addr,         // 0x100000 + CPU address
	input       [7:0] dl_data,

	// Writing the kept bytes back.
	output reg        bus_active = 0,
	output reg        bus_wr = 0,
	output reg [24:0] bus_addr = 0,
	output reg  [7:0] bus_dout = 0,

	// Instruction feed: sharpmz.vhd puts inj_data on the CPU data bus while inj_go. The CPU's M1, MREQ and RD
	// come back here so the feed starts at an opcode fetch and stops at the edge the last read ends on.
	input             m1_n,
	input             mreq_n,
	input             rd_n,
	output            inj_go,
	output      [7:0] inj_data
);

localparam [24:0] BASE = 25'h0100000;
localparam [15:0] LO = 16'h10F0, HI = 16'h11FF;
localparam integer WAIT_CLKS = CLK_HZ + CLK_HZ / 2;

reg  [7:0] keep[272];
reg [271:0] kept = 0;
wire [15:0] cpu_a = dl_addr[15:0];
wire        in_win = dl_addr[24:16] == BASE[24:16] && cpu_a >= LO && cpu_a <= HI;

// Header fields (MZF header at 10F0): load address 10F0+20, exec 10F0+22. Taken from the first write of each
// byte: a program that loads at 10F0 (Exploding Fist) then writes its body over the header.
reg  [15:0] fstrt = 0, fexec = 0;
reg   [7:0] ftype = 0;
reg         dl_active_d = 0;
reg         vblank_d = 0;

reg  [2:0] state = 0;
localparam S_IDLE = 0, S_LOAD = 1, S_WAIT = 2, S_RESTORE = 3, S_INJECT = 4, S_SYNC = 5;
reg [31:0] cnt = 0;
reg  [8:0] idx = 0;
reg  [1:0] pace = 0;

// The injected program.
reg  [7:0] prog[16];
reg  [3:0] plen = 0, pidx = 0;
reg        inj_arm = 0, started = 0, reading = 0;
assign inj_data = prog[pidx];
assign inj_go   = inj_arm & ~mreq_n & ~rd_n & (started | ~m1_n);

`ifdef DIRECT_START_DEBUG
reg [2:0] state_d = 0;
always @(posedge clk) begin
	state_d <= state;
	if (state != state_d) $display("direct_start: state %0d type %02x load %04x exec %04x en %b", state, ftype, fstrt, fexec, enable);
end
`endif

integer k;
always @(posedge clk) begin
	bus_wr <= 0;
	if (reset) begin
		state <= S_IDLE; inj_arm <= 0; bus_active <= 0;
	end
	else case (state)
	S_IDLE:
		if (dl_active) state <= S_LOAD;
	S_LOAD:
		if (dl_active) ;
		else if (enable & kept[23] & kept[22] & (ftype == 8'h01)) begin   // a machine-code program (type 01): start it
			cnt   <= 0;
			state <= S_WAIT;
		end
		else state <= S_IDLE;
	S_WAIT:
		if (dl_active) state <= S_LOAD;                   // another load: start over
		else if (cnt == WAIT_CLKS) begin
			idx <= 0; pace <= 0; bus_active <= 1;
			state <= S_RESTORE;
		end
		else cnt <= cnt + 1'd1;
	S_RESTORE:
		if (dl_active) begin bus_active <= 0; state <= S_LOAD; end
		else begin
			pace <= pace + 1'd1;
			if (pace == 0) begin
				if (idx == 9'd272) begin
					bus_active <= 0;
					// Build the program.
					k = 0;
					prog[k] = 8'h00; k = k + 1;                                       // NOP
					prog[k] = 8'hF3; k = k + 1;                                       // DI
					if (is_mz800) begin
						prog[k] = 8'hDB; prog[k+1] = 8'hE1; k = k + 2;                  // IN A,(E1)
						prog[k] = 8'hD3; prog[k+1] = 8'hE3; k = k + 2;                  // OUT (E3),A
					end
					if (has_e0 && fstrt < 16'h1000) begin
						prog[k] = 8'hD3; prog[k+1] = 8'hE0; k = k + 2;                  // OUT (E0),A
					end
					prog[k] = 8'h31; prog[k+1] = 8'hF0; prog[k+2] = 8'h10; k = k + 3;  // LD SP,10F0
					prog[k] = 8'hC3; prog[k+1] = fexec[7:0]; prog[k+2] = fexec[15:8]; k = k + 3;  // JP exec
					plen    <= k[3:0];
					pidx    <= 0;
					started <= 0;
					reading <= 0;
					state   <= S_SYNC;
				end
				else begin
					if (kept[idx]) begin
						bus_addr <= BASE + {9'd0, LO + {7'd0, idx}};
						bus_dout <= keep[idx];
						bus_wr   <= 1;
					end
					idx <= idx + 1'd1;
				end
			end
		end
	// Start at the start of vertical blanking, as mz800emu's direct load starts at a frame boundary: the program
	// then runs in the same phase against the display interrupts. Antiriad (Eng) plays a note per vblank interrupt
	// in a handler that runs about two frames; whether the title escapes to its credits depends on where a note ends
	// against the next vblank, so a start at an arbitrary raster point could miss it for ever.
	S_SYNC:
		if (dl_active) state <= S_LOAD;
		else if (vblank & ~vblank_d) begin inj_arm <= 1; state <= S_INJECT; end
	S_INJECT:
		if (dl_active) begin inj_arm <= 0; state <= S_LOAD; end
		else if (inj_go) begin
			reading <= 1;
`ifdef DIRECT_START_DEBUG
			if (!reading) $display("direct_start: read %0d m1_n=%b data=%02x", pidx, m1_n, inj_data);
`endif
		end
		else if (reading & rd_n) begin                   // one fed read finished
			reading <= 0;
			started <= 1;
			if (pidx + 1'd1 == plen) begin inj_arm <= 0; state <= S_IDLE; end
			else pidx <= pidx + 1'd1;
		end
	default: state <= S_IDLE;
	endcase

	vblank_d <= vblank;

	// Keep what the load writes to 10F0-11FF; a new load starts afresh (its first write can come with dl_active).
	dl_active_d <= dl_active;
	if (dl_active & ~dl_active_d) kept <= 0;
	if (dl_active & dl_wr & in_win) begin
		keep[cpu_a - LO] <= dl_data;
		kept[cpu_a - LO] <= 1;
		if (!kept[cpu_a - LO] | ~dl_active_d) case (cpu_a - LO)
			0:  ftype       <= dl_data;
			20: fstrt[7:0]  <= dl_data;
			21: fstrt[15:8] <= dl_data;
			22: fexec[7:0]  <= dl_data;
			23: fexec[15:8] <= dl_data;
			default: ;
		endcase
	end
end

endmodule
