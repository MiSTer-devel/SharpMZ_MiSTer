//=======================================================================================================
//
// Name:            tape_image.sv
// Description:     Tape image support for the SharpMZ core on MiSTer.
//
//                  A tape is an image mounted in an OSD "S" slot: an MZT file, i.e. MZF records
//                  (128-byte header + data) back to back, ended by a zero attribute byte or the end
//                  of the file. This module moves records between the image and the core's tape
//                  (CMT) buffer over the core's download bus, standing in for the tape handling the
//                  legacy HPS driver used to do:
//
//                    - Play: the record at the tape position is copied into the CMT buffer. When the
//                      machine has finished with it (the CMT clears PLAY_READY after the motor
//                      stops) the next record follows, so multi-part loaders work.
//                    - MZ-80B/2000 APSS: seek forward/back moves one record; eject rewinds.
//                    - Save: when the CMT has recorded a complete file (RECORD_READY), the header
//                      and data are read back and appended to the image after the last record.
//                    - Start direct (OSD Tape Image Start: Direct): on mounting, the first record goes
//                      into RAM as Load Direct puts it (header at 10F0, data at its load address,
//                      the machine held in reset, then started by direct_start.sv), and the tape is
//                      left at the second record, which a loader or BASIC then reads from the CMT.
//
//                  MiSTer can't grow a mounted image, so saving needs spare space in the file; a
//                  zero-filled blank tape works (the zero attribute marks the end of the tape).
//
// Copyright:       (C) 2026 The SharpMZ MiSTer contributors
//
//=======================================================================================================
// This source file is free software: you can redistribute it and-or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//=======================================================================================================

module tape_image
(
	input             clk,
	input             reset,

	// hps_io image slot.
	input             img_mounted,
	input             img_readonly,
	input      [63:0] img_size,
	output reg [31:0] sd_lba,
	output reg        sd_rd,
	output reg        sd_wr,
	input             sd_ack,
	input       [8:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	output      [7:0] sd_buff_din,
	input             sd_buff_wr,

	// Controls.
	input             rewind,          // Pulse: go back to the start of the tape.
	input             direct_first,    // On mounting, the first record goes to RAM (Load Direct), the tape to the second.
	output reg        ram_load = 0,    // Writing the first record to RAM: hold the machine in reset.
	input             host_busy,       // An OSD download is using the core bus (and may be filling the CMT); the engine holds still.
	input      [13:0] cmt_status,      // CMT_BUS_OUT from the core (see mctrl_pkg.vhd).

	// Core download bus (the core's ioctl interface). active is high while this module owns it.
	output reg        active,
	output reg [24:0] bus_addr,
	output reg        bus_wr,
	output reg  [7:0] bus_dout,
	input       [7:0] bus_din,
	input             bus_busy,        // The CMT data buffer (DDR3) is busy: hold writes, read data not ready yet.
	output            bus_rd,          // Reading bus_addr (S_CORE_RD), for the DDR3 buffer.

	// Status for the OSD/LEDs.
	output reg        mounted,
	output reg        tape_full,
	output reg  [7:0] record_no,

	// Messages for the overlay (tape_osd.sv): a pulse on msg with what happened.
	output reg        msg = 0,
	output reg  [1:0] msg_kind,        // 0 record ready (record_no), 1 end of tape, 2 saved, 3 full
	output reg  [7:0] rec_total = 0,   // records on the tape
	output reg[127:0] rec_name,        // header bytes 1-16 of the record (byte 1 in bits 7:0)
	output            rec_qd           // the record is an MZ-5Z001 Quick Disk BASIC file (type 02 loading at A215)
);

// CMT_BUS_OUT bit positions (mctrl_pkg.vhd).
localparam PLAY_READY   = 0;
localparam RECORD_READY = 2;
localparam RECORDING    = 3;
localparam APSS_SEEK    = 9;
localparam APSS_DIR     = 10;
localparam APSS_EJECT   = 11;

localparam [24:0] CMT_HDR  = 25'h0400000;
localparam [24:0] CMT_DATA = 25'h0410000;
localparam [24:0] SYSRAM   = 25'h0100000;     // + CPU address (the direct load's mapping)

// ------------------------------------------------------------------------------------------------
// Sector buffer: port A belongs to hps_io, port B to this module.
// ------------------------------------------------------------------------------------------------
reg  [8:0] buf_addr;
wire [7:0] buf_q;
reg  [7:0] buf_d;
reg        buf_we;

tape_sbuf sbuf
(
	.clk(clk),
	.addr_a(sd_buff_addr), .we_a(sd_buff_wr & sd_ack), .d_a(sd_buff_dout), .q_a(sd_buff_din),
	.addr_b(buf_addr),     .we_b(buf_we),              .d_b(buf_d),        .q_b(buf_q)
);

// ------------------------------------------------------------------------------------------------
// State machine. Byte-level operations on the image go through a one-sector write-back cache.
// ------------------------------------------------------------------------------------------------
typedef enum logic [5:0] {
	S_IDLE,
	// Scan the image for the end of the last record.
	S_SCAN, S_SCAN_ATTR, S_SCAN_LO, S_SCAN_HI,
	// Copy a record from the image into the CMT buffer.
	S_LOAD, S_LOAD_ATTR, S_LOAD_LO, S_LOAD_HI, S_LOAD_HDR, S_LOAD_HDR_WR, S_LOAD_DATA, S_LOAD_DATA_WR,
	// Append the recorded file to the image.
	S_SAVE, S_SAVE_LO, S_SAVE_HI, S_SAVE_CHECK, S_SAVE_COPY, S_SAVE_COPY_WR, S_SAVE_FLUSH,
	// Subroutines.
	S_IMG_RD, S_IMG_RD_WAIT, S_IMG_WR, S_ENSURE, S_FLUSH_WAIT_ACK, S_FLUSH_WAIT_DONE,
	S_FILL_WAIT_ACK, S_FILL_WAIT_DONE, S_CORE_RD, S_CORE_RD_WAIT
} state_t;

state_t state, ret, ret2;
assign  bus_rd = (state == S_CORE_RD) || (state == S_CORE_RD_WAIT);

reg [31:0] size;           // Image size in bytes (images up to 4 GB).
reg        readonly;
reg [31:0] rpos;           // Offset of the record in the CMT buffer (tape position).
reg [31:0] wpos;           // Offset after the last record (where saves go).
reg [31:0] pos;            // Scratch offset.
reg [16:0] len;            // Bytes of the current copy.
reg [16:0] cnt;
reg [15:0] rec_size;       // Data size of the record at rpos.
reg        loaded;         // The CMT buffer holds the record at rpos.
reg        direct_pending = 0;  // Start direct: the first record goes to RAM when it is loaded.
reg [15:0] load_addr;      // Its load address (header bytes 20-21).
reg  [7:0] rec_type;       // Its type (header byte 0).
assign rec_qd = (rec_type == 8'h02) & (load_addr == 16'hA215);

// Previous record offsets, for APSS seek back.
reg [31:0] hist[8];
reg  [2:0] hist_n;

// Image byte access.
reg [31:0] img_off;
reg  [7:0] img_byte;
reg [22:0] cache_lba;
reg        cache_valid, cache_dirty;
reg        wr_pending;      // S_ENSURE followed by a write rather than a read.
reg  [1:0] wait_cnt;

// Core bus access.
reg  [7:0] core_byte;

// Event detection.
reg [13:0] cmt_last;
reg        rewind_last;
reg        pending_rewind, pending_save, pending_next, pending_prev;
reg        pending_reload = 0;  // reload the current record into the CMT after a reset

wire [22:0] off_lba = img_off[31:9];

always @(posedge clk) begin
	buf_we <= 0;
	bus_wr <= 0;
	msg    <= 0;

	cmt_last    <= cmt_status;
	rewind_last <= rewind;

	// An OSD tape download replaces whatever this module put in the CMT buffer.
	if (host_busy) loaded <= 0;

`ifdef TAPE_IMAGE_DEBUG
	if (cmt_status[PLAY_READY] != cmt_last[PLAY_READY])
		$display("tape_image: PLAY_READY %b loaded %b state %0d mounted %b host_busy %b status %04x",
		         cmt_status[PLAY_READY], loaded, state, mounted, host_busy, cmt_status);
`endif
	// Latch events; they are serviced from S_IDLE.
	if (mounted & ~host_busy) begin
		if ((rewind & ~rewind_last) | (cmt_status[APSS_EJECT] & ~cmt_last[APSS_EJECT])) pending_rewind <= 1;
		if (cmt_status[RECORD_READY] & ~cmt_last[RECORD_READY]) pending_save <= 1;
		if (cmt_status[APSS_SEEK] & ~cmt_last[APSS_SEEK]) begin
			if (cmt_status[APSS_DIR]) pending_next <= 1;
			else pending_prev <= 1;
		end
		// The CMT drops PLAY_READY once the machine has stopped the tape after playing it.
		if (~cmt_status[PLAY_READY] & cmt_last[PLAY_READY] & ~cmt_status[RECORDING] & ~cmt_status[RECORD_READY] &
		    loaded & state == S_IDLE)
			pending_next <= 1;
	end

	if (img_mounted) begin
		size        <= |img_size[63:32] ? 32'hFFFFFFFF : img_size[31:0];
		readonly    <= img_readonly;
		mounted     <= |img_size;
		cache_valid <= 0;
		cache_dirty <= 0;
		loaded      <= 0;
		tape_full   <= 0;
		record_no   <= 0;
		hist_n      <= 0;
		rpos        <= 0;
		ram_load    <= 0;
		direct_pending <= direct_first & |img_size;
		pending_rewind <= 0; pending_save <= 0; pending_next <= 0; pending_prev <= 0; pending_reload <= 0;
		if (|img_size) begin
			pos    <= 0;
			active <= 1;
			state  <= S_SCAN;
		end else begin
			active <= 0;
			state  <= S_IDLE;
		end
	end
	// While an OSD download runs it owns the core bus, so the engine holds its state. It must not stall the
	// download instead (ioctl_wait): that freezes the whole HPS link, and with it the sector reads this engine
	// waits for. Main finishes any sector transfer before a download starts and serves none during one, so a
	// pending sd_rd/sd_wr simply waits.
	else if (host_busy) begin
	end
	else case (state)

	S_IDLE: begin
		active <= 0;
		if (mounted & ~host_busy) begin
			if (pending_save) begin
				pending_save <= 0;
				active <= 1;
				state  <= S_SAVE;
			end
			else if (pending_reload) begin                  // rescan for the end of the tape, then load rpos
				pending_reload <= 0;
				pos       <= 0;
				active    <= 1;
				state     <= S_SCAN;
			end
			else if (pending_rewind) begin
				pending_rewind <= 0; pending_next <= 0; pending_prev <= 0;
				rpos      <= 0;
				hist_n    <= 0;
				record_no <= 0;
				active    <= 1;
				state     <= S_LOAD;
			end
			else if (pending_next) begin
				pending_next <= 0;
				if (loaded) begin
					hist[hist_n] <= rpos;
					if (hist_n != 7) hist_n <= hist_n + 1'd1;
					rpos      <= rpos + 32'd128 + rec_size;
					record_no <= record_no + 1'd1;
					active    <= 1;
					state     <= S_LOAD;
				end
			end
			else if (pending_prev) begin
				pending_prev <= 0;
				if (hist_n != 0) begin
					rpos      <= hist[hist_n - 1'd1];
					hist_n    <= hist_n - 1'd1;
					record_no <= record_no - 1'd1;
				end
				active <= 1;
				state  <= S_LOAD;
			end
		end
	end

	// ---- Find the end of the recorded area --------------------------------------------------
	S_SCAN: begin
		if (pos == 0) rec_total <= 0;
		if (pos + 32'd128 > size) begin
			wpos  <= pos;
			state <= S_LOAD;
		end else begin
			img_off <= pos; ret <= S_SCAN_ATTR; state <= S_IMG_RD;
		end
	end
	S_SCAN_ATTR: begin
		if (img_byte == 8'h00) begin
			wpos  <= pos;
			state <= S_LOAD;
		end else begin
			img_off <= pos + 32'd18; ret <= S_SCAN_LO; state <= S_IMG_RD;
		end
	end
	S_SCAN_LO: begin
		len[7:0] <= img_byte;
		img_off  <= pos + 32'd19; ret <= S_SCAN_HI; state <= S_IMG_RD;
	end
	S_SCAN_HI: begin
		rec_total <= rec_total + 1'd1;
		pos   <= pos + 32'd128 + {img_byte, len[7:0]};
		state <= S_SCAN;
	end

	// ---- Copy the record at rpos into the CMT buffer ---------------------------------------
	S_LOAD: begin
		loaded <= 0;
		if (rpos + 32'd128 > size) begin                       // End of tape.
			msg <= 1; msg_kind <= 2'd1;
			state <= S_IDLE;
		end
		else begin
			img_off <= rpos; ret <= S_LOAD_ATTR; state <= S_IMG_RD;
		end
	end
	S_LOAD_ATTR: begin
		if (img_byte == 8'h00) begin                            // End of tape.
			msg <= 1; msg_kind <= 2'd1;
			state <= S_IDLE;
		end
		else begin
			img_off <= rpos + 32'd18; ret <= S_LOAD_LO; state <= S_IMG_RD;
		end
	end
	S_LOAD_LO: begin
		rec_size[7:0] <= img_byte;
		img_off <= rpos + 32'd19; ret <= S_LOAD_HI; state <= S_IMG_RD;
	end
	S_LOAD_HI: begin
		rec_size[15:8] <= img_byte;
		cnt   <= 0;
		if (direct_pending & rpos == 0) ram_load <= 1;          // start direct: this record goes to RAM
		direct_pending <= 0;
		state <= S_LOAD_HDR;
	end
	S_LOAD_HDR: begin
		if (cnt == 17'd128) begin
			cnt   <= 0;
			state <= S_LOAD_DATA;
		end else begin
			img_off <= rpos + cnt; ret <= S_LOAD_HDR_WR; state <= S_IMG_RD;
		end
	end
	S_LOAD_HDR_WR: if (!bus_busy) begin
		if (cnt >= 17'd1 && cnt <= 17'd16) rec_name[8*(cnt[3:0] - 4'd1) +: 8] <= img_byte;
		if (cnt == 17'd0)  rec_type <= img_byte;
		if (cnt == 17'd20) load_addr[7:0]  <= img_byte;
		if (cnt == 17'd21) load_addr[15:8] <= img_byte;
		bus_addr <= ram_load ? SYSRAM + 25'h10F0 + cnt[6:0] : CMT_HDR + cnt[6:0];
		bus_dout <= img_byte;
		bus_wr   <= 1;
		cnt      <= cnt + 1'd1;
		state    <= S_LOAD_HDR;
	end
	S_LOAD_DATA: begin
		if ((cnt == {1'b0, rec_size} || rpos + 32'd128 + cnt >= size) && ram_load) begin
			// In RAM: let the machine go (SharpMZ.sv then resets it once more and direct_start.sv starts the
			// program) and put the tape at the next record, which the reset reloads into the CMT.
			ram_load  <= 0;
			hist[0]   <= rpos;
			hist_n    <= 1;
			rpos      <= rpos + 32'd128 + rec_size;
			record_no <= record_no + 1'd1;
			state     <= S_LOAD;
		end
		else if (cnt == {1'b0, rec_size} || rpos + 32'd128 + cnt >= size) begin
			loaded <= 1;
			msg <= 1; msg_kind <= 2'd0;
			state  <= S_IDLE;
		end else begin
			img_off <= rpos + 32'd128 + cnt; ret <= S_LOAD_DATA_WR; state <= S_IMG_RD;
		end
	end
	S_LOAD_DATA_WR: if (!bus_busy) begin
		bus_addr <= ram_load ? SYSRAM + {9'd0, load_addr + cnt[15:0]} : CMT_DATA + cnt[15:0];
		bus_dout <= img_byte;
		bus_wr   <= 1;
		cnt      <= cnt + 1'd1;
		state    <= S_LOAD_DATA;
	end

	// ---- Append the recorded file ------------------------------------------------------------
	S_SAVE: begin
		bus_addr <= CMT_HDR + 25'd18; ret2 <= S_SAVE_LO; state <= S_CORE_RD;
	end
	S_SAVE_LO: begin
		len[7:0] <= core_byte;
		bus_addr <= CMT_HDR + 25'd19; ret2 <= S_SAVE_HI; state <= S_CORE_RD;
	end
	S_SAVE_HI: begin
		len   <= 17'd128 + {core_byte, len[7:0]};
		state <= S_SAVE_CHECK;
	end
	S_SAVE_CHECK: begin
		cnt <= 0;
		if (readonly || wpos + len > size) begin
			tape_full <= 1;
			msg <= 1; msg_kind <= 2'd3;
			state     <= S_IDLE;
		end
		else state <= S_SAVE_COPY;
	end
	S_SAVE_COPY: begin
		if (cnt == len) state <= S_SAVE_FLUSH;
		else begin
			bus_addr <= (cnt < 17'd128) ? CMT_HDR + cnt[6:0] : CMT_DATA + (cnt[15:0] - 16'd128);
			ret2  <= S_SAVE_COPY_WR;
			state <= S_CORE_RD;
		end
	end
	S_SAVE_COPY_WR: begin
		if (cnt >= 17'd1 && cnt <= 17'd16) rec_name[8*(cnt[3:0] - 4'd1) +: 8] <= core_byte;
		img_off  <= wpos + cnt;
		img_byte <= core_byte;
		cnt      <= cnt + 1'd1;
		ret      <= S_SAVE_COPY;
		state    <= S_IMG_WR;
	end
	S_SAVE_FLUSH: begin
		// Write the last sector back; img_off beyond the cached sector forces the flush.
		if (cache_dirty) begin
			sd_lba <= cache_lba;
			sd_wr  <= 1;
			ret    <= S_SAVE_FLUSH;
			state  <= S_FLUSH_WAIT_ACK;
		end else begin
			wpos  <= wpos + len;
			msg <= 1; msg_kind <= 2'd2;
			rec_total <= rec_total + 1'd1;                     // (the overlay shows SAVED and the new record's number)
			state <= S_IDLE;
		end
	end

	// ---- Subroutine: img_byte <= image[img_off] -----------------------------------------------
	S_IMG_RD: begin
		wr_pending <= 0;
		state      <= S_ENSURE;
	end
	S_IMG_RD_WAIT: begin
		if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'd1;
		else begin
			img_byte <= buf_q;
			state    <= ret;
		end
	end

	// ---- Subroutine: image[img_off] <= img_byte -----------------------------------------------
	S_IMG_WR: begin
		wr_pending <= 1;
		state      <= S_ENSURE;
	end

	// Make the sector holding img_off the cached one, then do the pending read or write.
	S_ENSURE: begin
		if (cache_valid && cache_lba == off_lba) begin
			buf_addr <= img_off[8:0];
			if (wr_pending) begin
				buf_d       <= img_byte;
				buf_we      <= 1;
				cache_dirty <= 1;
				state       <= ret;
			end else begin
				wait_cnt <= 2'd2;
				state    <= S_IMG_RD_WAIT;
			end
		end
		else if (cache_valid && cache_dirty) begin
			sd_lba <= cache_lba;
			sd_wr  <= 1;
			state  <= S_FLUSH_WAIT_ACK;
		end
		else begin
			sd_lba      <= off_lba;
			sd_rd       <= 1;
			cache_valid <= 0;
			state       <= S_FILL_WAIT_ACK;
		end
	end
	S_FLUSH_WAIT_ACK:  if (sd_ack) begin sd_wr <= 0; state <= S_FLUSH_WAIT_DONE; end
	S_FLUSH_WAIT_DONE: if (!sd_ack) begin
		cache_dirty <= 0;
		state <= (ret == S_SAVE_FLUSH) ? S_SAVE_FLUSH : S_ENSURE;
	end
	S_FILL_WAIT_ACK:   if (sd_ack) begin sd_rd <= 0; state <= S_FILL_WAIT_DONE; end
	S_FILL_WAIT_DONE:  if (!sd_ack) begin
		cache_lba   <= sd_lba;
		cache_valid <= 1;
		cache_dirty <= 0;
		state       <= S_ENSURE;
	end

	// ---- Subroutine: core_byte <= core[bus_addr] ----------------------------------------------
	// The CMT buffers are synchronous RAMs; allow two clocks for the read data.
	S_CORE_RD: begin
		wait_cnt <= 2'd2;
		state    <= S_CORE_RD_WAIT;
	end
	S_CORE_RD_WAIT: begin
		if (wait_cnt != 0 || bus_busy) begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'd1; end
		else begin
			core_byte <= bus_din;
			state     <= ret2;
		end
	end

	default: state <= S_IDLE;
	endcase

	// A reset keeps the image (it used to unmount it, so a tape mounted before pressing Reset was lost):
	// any transfer is dropped and the current record is loaded into the CMT again.
	if (reset) begin
		state   <= S_IDLE;
		active  <= 0;
		ram_load <= 0;
		sd_rd   <= 0;
		sd_wr   <= 0;
		loaded  <= 0;
		if (~cache_dirty) cache_valid <= 0;
		pending_reload <= mounted;
		pending_rewind <= 0; pending_save <= 0; pending_next <= 0; pending_prev <= 0;
	end
end

endmodule

// 512-byte true dual-port block RAM for the sector buffer.
module tape_sbuf
(
	input            clk,
	input      [8:0] addr_a,
	input            we_a,
	input      [7:0] d_a,
	output reg [7:0] q_a,
	input      [8:0] addr_b,
	input            we_b,
	input      [7:0] d_b,
	output reg [7:0] q_b
);

(* ramstyle = "M10K, no_rw_check" *) reg [7:0] ram[512];

always @(posedge clk) begin
	if (we_a) begin
		ram[addr_a] <= d_a;
		q_a <= d_a;
	end
	else q_a <= ram[addr_a];
end

always @(posedge clk) begin
	if (we_b) begin
		ram[addr_b] <= d_b;
		q_b <= d_b;
	end
	else q_b <= ram[addr_b];
end

endmodule
