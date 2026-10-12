//============================================================================
//
//  Sharp MZ printer port to the MiSTer UART (OSD Printer: UART).
//
//  The MZ-700 (I/O FE/FF) and the MZ-800/1500 (Z80 PIO: port B data, PA7 RDP, PA0 RDA) drive a parallel
//  printer with the same handshake (MZ-800 Technical Reference Manual, 7 Printer interface; MZ-700 BASIC
//  1Z-013B at 2871): wait for RDA low, put the byte on the data port, raise RDP, wait for RDA high, drop
//  RDP. This module is the printer: it takes the byte on the rising edge of RDP and answers RDA = RDP
//  (an acknowledge for every strobe), held high while its buffer is full. The bytes are sent out of the
//  MiSTer UART, 8N1 at the speed chosen in Main's UART menu (9600 if none), for the printer daemon on
//  the HPS (mister_printerd: Epson text and graphics to PDF).
//
//  Copyright (C) 2026 SharpMZ MiSTer contributors. GPL v2 or later.
//
//============================================================================

module mz_printer #(parameter CLK_HZ = 70937600)
(
	input             clk,
	input             reset,
	input             enable,          // OSD Printer: UART
	input             ascii,           // OSD Printer Charset: ASCII (Sharp codes converted, CR followed by LF)
	input             rdp,             // strobe from the machine, active high (MZ standard)
	input       [7:0] data,
	output            rda,             // to the machine: high = busy / acknowledge
	input      [31:0] uart_speed,      // from hps_io (0 = not set)
	output reg        txd = 1'b1,
	output     [15:0] count            // bytes taken since reset (for the OSD / debugging)
);

// 512-byte FIFO.
reg  [7:0] fifo[512];
reg  [9:0] wp = 0, rp = 0;
wire [9:0] used = wp - rp;
wire       full = used[9];
wire       empty = (wp == rp);

reg        rdp_l = 0;
reg [15:0] taken = 0;
assign count = taken;

// Sharp ASCII to ASCII (the first half of rtl/software/mif/ascii_conv.mif, which the tape name option uses):
// lowercase and the symbols move to their ASCII codes, graphics characters become spaces, 00-1F pass through.
// For printers that aren't Sharp's (the daemon's Epson model); a Sharp printer or plotter wants the Sharp codes.
function automatic [7:0] sharp2ascii(input [7:0] c);
	begin
		case (c)
			8'h60: sharp2ascii = 8'h20;
			8'h61: sharp2ascii = 8'h20;
			8'h62: sharp2ascii = 8'h20;
			8'h63: sharp2ascii = 8'h20;
			8'h64: sharp2ascii = 8'h20;
			8'h65: sharp2ascii = 8'h20;
			8'h66: sharp2ascii = 8'h20;
			8'h67: sharp2ascii = 8'h20;
			8'h68: sharp2ascii = 8'h20;
			8'h69: sharp2ascii = 8'h20;
			8'h6A: sharp2ascii = 8'h20;
			8'h6B: sharp2ascii = 8'h20;
			8'h6C: sharp2ascii = 8'h20;
			8'h6D: sharp2ascii = 8'h20;
			8'h6E: sharp2ascii = 8'h20;
			8'h6F: sharp2ascii = 8'h20;
			8'h70: sharp2ascii = 8'h20;
			8'h71: sharp2ascii = 8'h20;
			8'h72: sharp2ascii = 8'h20;
			8'h73: sharp2ascii = 8'h20;
			8'h74: sharp2ascii = 8'h20;
			8'h75: sharp2ascii = 8'h20;
			8'h76: sharp2ascii = 8'h20;
			8'h77: sharp2ascii = 8'h20;
			8'h78: sharp2ascii = 8'h20;
			8'h79: sharp2ascii = 8'h20;
			8'h7A: sharp2ascii = 8'h20;
			8'h7B: sharp2ascii = 8'h20;
			8'h7C: sharp2ascii = 8'h20;
			8'h7D: sharp2ascii = 8'h20;
			8'h7E: sharp2ascii = 8'h20;
			8'h7F: sharp2ascii = 8'h20;
			8'h80: sharp2ascii = 8'h7D;
			8'h81: sharp2ascii = 8'h20;
			8'h82: sharp2ascii = 8'h20;
			8'h83: sharp2ascii = 8'h20;
			8'h84: sharp2ascii = 8'h20;
			8'h85: sharp2ascii = 8'h20;
			8'h86: sharp2ascii = 8'h20;
			8'h87: sharp2ascii = 8'h20;
			8'h88: sharp2ascii = 8'h20;
			8'h89: sharp2ascii = 8'h20;
			8'h8A: sharp2ascii = 8'h20;
			8'h8B: sharp2ascii = 8'h5E;
			8'h8C: sharp2ascii = 8'h20;
			8'h8D: sharp2ascii = 8'h20;
			8'h8E: sharp2ascii = 8'h20;
			8'h8F: sharp2ascii = 8'h20;
			8'h90: sharp2ascii = 8'h5F;
			8'h91: sharp2ascii = 8'h20;
			8'h92: sharp2ascii = 8'h65;
			8'h93: sharp2ascii = 8'h88;
			8'h94: sharp2ascii = 8'h7E;
			8'h95: sharp2ascii = 8'h20;
			8'h96: sharp2ascii = 8'h74;
			8'h97: sharp2ascii = 8'h67;
			8'h98: sharp2ascii = 8'h68;
			8'h99: sharp2ascii = 8'h20;
			8'h9A: sharp2ascii = 8'h62;
			8'h9B: sharp2ascii = 8'h78;
			8'h9C: sharp2ascii = 8'h64;
			8'h9D: sharp2ascii = 8'h72;
			8'h9E: sharp2ascii = 8'h70;
			8'h9F: sharp2ascii = 8'h63;
			8'hA0: sharp2ascii = 8'h71;
			8'hA1: sharp2ascii = 8'h61;
			8'hA2: sharp2ascii = 8'h7A;
			8'hA3: sharp2ascii = 8'h77;
			8'hA4: sharp2ascii = 8'h73;
			8'hA5: sharp2ascii = 8'h75;
			8'hA6: sharp2ascii = 8'h69;
			8'hA7: sharp2ascii = 8'h20;
			8'hA8: sharp2ascii = 8'hD6;
			8'hA9: sharp2ascii = 8'h6B;
			8'hAA: sharp2ascii = 8'h66;
			8'hAB: sharp2ascii = 8'h76;
			8'hAC: sharp2ascii = 8'h20;
			8'hAD: sharp2ascii = 8'hFC;
			8'hAE: sharp2ascii = 8'hDF;
			8'hAF: sharp2ascii = 8'h6A;
			8'hB0: sharp2ascii = 8'h6E;
			8'hB1: sharp2ascii = 8'h20;
			8'hB2: sharp2ascii = 8'hDC;
			8'hB3: sharp2ascii = 8'h6D;
			8'hB4: sharp2ascii = 8'h20;
			8'hB5: sharp2ascii = 8'h20;
			8'hB6: sharp2ascii = 8'h20;
			8'hB7: sharp2ascii = 8'h6F;
			8'hB8: sharp2ascii = 8'h6C;
			8'hB9: sharp2ascii = 8'hC4;
			8'hBA: sharp2ascii = 8'hF6;
			8'hBB: sharp2ascii = 8'hE4;
			8'hBC: sharp2ascii = 8'h20;
			8'hBD: sharp2ascii = 8'h79;
			8'hBE: sharp2ascii = 8'h7B;
			8'hBF: sharp2ascii = 8'h20;
			8'hC0: sharp2ascii = 8'h7C;
			8'hC1: sharp2ascii = 8'h20;
			8'hC2: sharp2ascii = 8'h20;
			8'hC3: sharp2ascii = 8'h20;
			8'hC4: sharp2ascii = 8'h20;
			8'hC5: sharp2ascii = 8'h20;
			8'hC6: sharp2ascii = 8'h20;
			8'hC7: sharp2ascii = 8'h20;
			8'hC8: sharp2ascii = 8'h20;
			8'hC9: sharp2ascii = 8'h20;
			8'hCA: sharp2ascii = 8'h20;
			8'hCB: sharp2ascii = 8'h20;
			8'hCC: sharp2ascii = 8'h20;
			8'hCD: sharp2ascii = 8'h20;
			8'hCE: sharp2ascii = 8'h20;
			8'hCF: sharp2ascii = 8'h20;
			8'hD0: sharp2ascii = 8'h20;
			8'hD1: sharp2ascii = 8'h20;
			8'hD2: sharp2ascii = 8'h20;
			8'hD3: sharp2ascii = 8'h20;
			8'hD4: sharp2ascii = 8'h20;
			8'hD5: sharp2ascii = 8'h20;
			8'hD6: sharp2ascii = 8'h20;
			8'hD7: sharp2ascii = 8'h20;
			8'hD8: sharp2ascii = 8'h20;
			8'hD9: sharp2ascii = 8'h20;
			8'hDA: sharp2ascii = 8'h20;
			8'hDB: sharp2ascii = 8'h20;
			8'hDC: sharp2ascii = 8'h20;
			8'hDD: sharp2ascii = 8'h20;
			8'hDE: sharp2ascii = 8'h20;
			8'hDF: sharp2ascii = 8'h20;
			8'hE0: sharp2ascii = 8'h20;
			8'hE1: sharp2ascii = 8'h20;
			8'hE2: sharp2ascii = 8'h20;
			8'hE3: sharp2ascii = 8'h20;
			8'hE4: sharp2ascii = 8'h20;
			8'hE5: sharp2ascii = 8'h20;
			8'hE6: sharp2ascii = 8'h20;
			8'hE7: sharp2ascii = 8'h20;
			8'hE8: sharp2ascii = 8'h20;
			8'hE9: sharp2ascii = 8'h20;
			8'hEA: sharp2ascii = 8'h20;
			8'hEB: sharp2ascii = 8'h20;
			8'hEC: sharp2ascii = 8'h20;
			8'hED: sharp2ascii = 8'h20;
			8'hEE: sharp2ascii = 8'h20;
			8'hEF: sharp2ascii = 8'h20;
			8'hF0: sharp2ascii = 8'h20;
			8'hF1: sharp2ascii = 8'h20;
			8'hF2: sharp2ascii = 8'h20;
			8'hF3: sharp2ascii = 8'h20;
			8'hF4: sharp2ascii = 8'h20;
			8'hF5: sharp2ascii = 8'h20;
			8'hF6: sharp2ascii = 8'h20;
			8'hF7: sharp2ascii = 8'h20;
			8'hF8: sharp2ascii = 8'h20;
			8'hF9: sharp2ascii = 8'h20;
			8'hFA: sharp2ascii = 8'h20;
			8'hFB: sharp2ascii = 8'hA3;
			8'hFC: sharp2ascii = 8'h20;
			8'hFD: sharp2ascii = 8'h20;
			8'hFE: sharp2ascii = 8'h20;
			8'hFF: sharp2ascii = 8'h20;
			default: sharp2ascii = c;
		endcase
	end
endfunction
wire [7:0] conv = ascii ? sharp2ascii(data) : data;
reg        lf_pend = 0;              // ASCII: a CR is followed by an LF (a Sharp printer takes CR as a new line)
reg        lf_sent = 0;              // and an LF the program sends after its CR is then dropped (no blank line)
assign rda   = enable & (rdp | full);

always @(posedge clk) begin
	rdp_l <= rdp;
	if (reset) begin
		wp      <= 0;
		taken   <= 0;
		lf_pend <= 0;
		lf_sent <= 0;
	end
	else if (lf_pend) begin
		if (~full) begin
			fifo[wp[8:0]] <= 8'h0A;
			wp      <= wp + 1'd1;
			lf_pend <= 0;
			lf_sent <= 1;
		end
	end
	else if (enable & rdp & ~rdp_l & ~full) begin
		taken   <= taken + 1'd1;
		lf_sent <= 0;
		if (~(ascii && lf_sent && data == 8'h0A)) begin
			fifo[wp[8:0]] <= conv;
			wp <= wp + 1'd1;
		end
		if (ascii && data == 8'h0D) lf_pend <= 1;
	end
end

// UART transmitter, 8N1. The bit time is a fractional accumulator (adds the baud rate every clock, a bit
// ends when it passes CLK_HZ), so any speed Main offers works without a divider.
wire [31:0] baud = (uart_speed == 0 || uart_speed > CLK_HZ / 4) ? 32'd9600 : uart_speed;
reg  [31:0] acc = 0;
reg   [3:0] bitn = 0;                   // 0 idle, 1 start, 2-9 data, 10 stop
reg   [7:0] sh = 0;
wire [32:0] acc_next = acc + baud;
wire        bit_end = acc_next >= CLK_HZ;

always @(posedge clk) begin
	if (reset | ~enable) begin
		txd  <= 1'b1;
		bitn <= 0;
		rp   <= wp;                     // drop what is queued
	end
	else if (bitn == 0) begin
		if (~empty) begin
			sh   <= fifo[rp[8:0]];
			rp   <= rp + 1'd1;
			acc  <= 0;
			bitn <= 1;
			txd  <= 1'b0;               // start bit
		end
	end
	else if (bit_end) begin
		acc <= acc_next[31:0] - CLK_HZ;
		if (bitn == 10) begin
			bitn <= 0;
		end
		else begin
			bitn <= bitn + 1'd1;
			if (bitn == 9) txd <= 1'b1; // stop bit
			else begin
				txd <= sh[0];
				sh  <= {1'b0, sh[7:1]};
			end
		end
	end
	else acc <= acc_next[31:0];
end

endmodule
