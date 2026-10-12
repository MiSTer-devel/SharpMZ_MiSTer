
// ====================================================================
//
//  WD1793, WD1772, WD1773 replica (with write capability)
//
//  Copyright (C) 2007,2008 Viacheslav Slavinsky
//  Copyright (C) 2016 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module wd1793 #(parameter RWMODE=0, EDSK=1)
(
	input        clk_sys,     // sys clock
	input        ce,          // ce at CPU clock rate
	input        reset,	     // async reset
	input        io_en,
	input        rd,          // i/o read
	input        wr,          // i/o write
	input  [1:0] addr,        // i/o port addr
	input  [7:0] din,         // i/o data in
	output [7:0] dout,        // i/o data out
	output       drq,         // DMA request
	output       intrq,
	output       busy,

	input        wp,          // write protect
	input        crc_report,  // LOCAL ADDITION (SharpMZ): report sectors dumped with a CRC error (.d77 status, EDSK ST1/ST2)

	// LOCAL ADDITION (FM-7_MiSTer): write-protect flag carried inside the image
	// itself. .d77 has one at header offset $1a; valid only once the mount-time
	// scan has finished (i.e. when `prepare` falls). OR it into `wp` upstream.
	output       fmt_wp,

	input  [2:0] size_code,
	input        layout,      // 0 = Track-Side-Sector, 1 - Side-Track-Sector
	input        side,
	input        ready,

	// SD access (RWMODE == 1)
	input        img_mounted, // signaling that new image has been mounted
	input [20:0] img_size,    // size of image in bytes. 2MB MAX (1.44 MB EDSK images are ~1.5 MB).
	// The TRUE image size, untruncated. A .d77 multi-disk container is routinely
	// larger than 1 MB (XANADU.D77 is 2.4 MB, six disks), and comparing its
	// header size field against the truncated img_size can never match:
	// 2495040 & $FFFFF = 397888, against a 415840 field.
	//
	// Used for format identification AND for the scan bound (see scan_limit).
	// (Superseded claim: "for format identification only ... the addressing
	// below stays 20-bit and reaches only the first disk, which is all any of
	// these titles boots from." The masking WRAPS rather than clamps, so a
	// container is not guaranteed to reach even its first disk -- that is what
	// blanked Ys - Ancient Ys Vanished Omen [a]. Addressing is still 20-bit and
	// still reaches only the first disk; the BOUND is what had to change.)
	input [23:0] img_size_id,

	// Which disk inside a multi-disk container to present, 0-based.
	//
	// A .d77/.d88 container is several complete images concatenated, each with
	// its own header and its own track table whose offsets are relative to ITS
	// OWN start. 51 distinct containers in the Neo Kobe set hold 132 sub-disks
	// between them (2x, 3x, 4x, 5x and 6x), and until this existed only the
	// first of each was reachable -- a six-disk game booted and could never be
	// swapped. Selecting disk 0 is bit-identical to the previous behaviour,
	// because d_base is then 0 and every relative address equals the absolute
	// one.
	input  [2:0] disk_index,
	output       prepare,
	output[31:0] sd_lba,
	output reg   sd_rd,
	output reg   sd_wr,
	input        sd_ack,
	input  [8:0] sd_buff_addr,
	input  [7:0] sd_buff_dout,
	output [7:0] sd_buff_din,
	input        sd_buff_wr,

	// RAM access (RWMODE == 0)
	input        input_active,
	input [20:0] input_addr,
	input  [7:0] input_data,
	input        input_wr,
	output[20:0] buff_addr,	  // buffer RAM address
	output       buff_read,	  // buffer RAM read enable
	input  [7:0] buff_din     // buffer RAM data input
);

// Possible track configs:
// 0: 26 x 128  = 3.3KB
// 1: 16 x 256  = 4.0KB
// 2:  9 x 512  = 4.5KB
// 3:  5 x 1024 = 5.0KB
// 4: 10 x 512  = 5.0KB

assign dout      = q;
assign drq       = s_drq;
assign busy      = s_busy;
assign intrq     = s_intrq;
assign sd_lba    = scan_active ? scan_addr[20:9] : buff_a[20:9] + sd_block;
assign prepare   = EDSK ? scan_active : img_mounted;
assign buff_addr = {buff_a[20:9], 9'd0} + byte_addr;
assign buff_read = ((addr == A_DATA) && buff_rd);

reg   [7:0] sectors_per_track, edsk_spt = 0;
wire [10:0] sector_size = 11'd128 << wd_size_code;
reg  [10:0] byte_addr;
reg  [20:0] buff_a;
reg   [1:0] wd_size_code;

wire  [7:0] buff_dout;
reg   [1:0] sd_block = 0;
reg         format;
generate
	if(RWMODE) begin
		wd1793_dpram sbuf
		(
			.clock(clk_sys),

			.address_a({sd_block, sd_buff_addr}),
			.data_a(sd_buff_dout),
			.wren_a(sd_buff_wr & sd_ack),
			.q_a(sd_buff_din),

			.address_b(scan_active ? {2'b00, scan_addr[8:0]} : byte_addr),
			.data_b(format ? 8'd0 : din),
			.wren_b(wre & buff_wr & (addr == A_DATA) & ~scan_active),
			.q_b(buff_dout)
		);
	end else begin
		assign buff_dout   = 0;
		assign sd_buff_din = 0;
	end
endgenerate

reg         var_size  = 0;
reg  [20:0] disk_size;
reg         layout_r;

// Bound for the mount-time D77 scan. It must be min(true size, the 20-bit
// address space) -- NOT img_size, which is the true size masked to 20 bits.
//
// The mask WRAPS, it does not clamp, and that is the whole bug. Ys - Ancient Ys
// Vanished Omen [a] is a 1,305,456-byte multi-disk container: 1305456 & $FFFFF
// = 256,880, which is SMALLER than the container's own first disk (415,840).
// The scan therefore stopped 80.3% of the way short of the file and every track
// from index 50 (track 25 side 0) on was never entered in the table. The title
// boots and runs -- the early tracks are all present -- and then its loader asks
// for track 33 side 0 sector 4 at offset 343,040, gets RECORD NOT FOUND, and
// retries: 4,242 read commands against the reference's 64, no VRAM write ever
// issued, black screen.
//
// XANADU.D77 has the same defect and survived it: 2,495,040 wraps to 397,888
// against a 415,840-byte first disk, so it loses only its tail.
//
// Under 1 MB this is bit-identical to the old expression, so ordinary single
// disk images are untouched -- the gate is unchanged, every counter included.
// The image size at mount: hps_io's img_size is one bus shared by every image slot, so mounting another drive
// while this image is still being scanned changed the limit under the scanner.
reg  [23:0] size_id_r = 0;
wire [20:0] scan_limit = (size_id_r[23:21] != 3'd0) ? 21'h1FFFFF
                                                    : size_id_r[20:0];
wire [20:0] hs  = (layout_r & side) ? disk_size >> 1 : 21'd0;
wire  [7:0] dts = {disk_track[6:0], side} >> layout_r;
always @(posedge clk_sys) begin
	case({var_size,size_code})
				0: buff_a <= hs + {{1'b0, dts, 4'b0000} + {dts, 3'b000} + {dts, 1'b0} + wdreg_sector - 1'd1,  7'd0};
				1: buff_a <= hs + {{dts, 4'b0000}                                     + wdreg_sector - 1'd1,  8'd0};
				2: buff_a <= hs + {{dts, 3'b000}  + dts                               + wdreg_sector - 1'd1,  9'd0};
				3: buff_a <= hs + {{dts, 2'b00}   + dts                               + wdreg_sector - 1'd1, 10'd0};
				4: buff_a <= hs + {{dts, 3'b000}  +{dts, 1'b0}                        + wdreg_sector - 1'd1,  9'd0};
		default: buff_a <= edsk_offset;
	endcase
	case({var_size,size_code})
				0: sectors_per_track <= 26;
				1: sectors_per_track <= 16;
				2: sectors_per_track <= 9;
				3: sectors_per_track <= 5;
				4: sectors_per_track <= 10;
		default: sectors_per_track <= edsk_spt;
	endcase
	case({var_size,size_code})
				0: wd_size_code <= 0;
				1: wd_size_code <= 1;
				2: wd_size_code <= 2;
				3: wd_size_code <= 3;
				4: wd_size_code <= 2;
		default: wd_size_code <= edsk_sizecode;
	endcase
end

// blk_size is the number of 512-byte blocks to fetch BEYOND the first, so that
// a sector whose data crosses a block boundary is fully present in the buffer.
//
// LOCAL CHANGE (FM-7_MiSTer): the original hardcoded 0 for size codes 0 and 1,
// which is only right when 128/256-byte sectors are 512-aligned. A .d77 stores
// sectors as a 16-byte header immediately followed by the data, so with the
// usual 256-byte sectors the stride is 272 and the data is essentially never
// aligned -- 593 of the 1265 sectors in the Thexder image straddle a boundary,
// and every one of them would have read the second half from a stale buffer.
// Replaced by the general expression, which reproduces the original values for
// size codes 2 and 3.
wire [11:0] blk_last = {3'b000, buff_a[8:0]} + sector_size - 1'd1;
wire  [1:0] blk_size = blk_last[10:9];


// Register addresses
localparam A_COMMAND         = 0;
localparam A_STATUS          = 0;
localparam A_TRACK           = 1;
localparam A_SECTOR          = 2;
localparam A_DATA            = 3;

// States
typedef enum 
{
	STATE_IDLE,

	STATE_SEARCH,
	STATE_SEARCH_1,

	STATE_WAIT_READ,
	STATE_WAIT_READ_1,
	STATE_WAIT_READ_2,

	STATE_READ,
	STATE_READ_1,
	STATE_READ_2,
	STATE_READ_3,

	STATE_WAIT_WRITE,
	STATE_WAIT_WRITE_1,
	STATE_WAIT_WRITE_2,

	STATE_WRITE,
	STATE_WRITE_1,
	STATE_WRITE_2,

	STATE_ABORT,
	STATE_WAIT,
	STATE_WAIT_2,
	STATE_ENDCOMMAND
} io_state_t;


// common status bits
// An empty drive reports NOT write-protected. 77AVEMU's WriteProtected() reads
// the mounted image's flag and returns false when the drive holds no image
// (refs/TOWNSEMU/src/diskdrive/diskdrive.cpp:1363-1371), so `ready` gates it
// here. Without that an unmounted slot came back $d4 instead of $84, because
// FDC.v starts wp_r at 2'b11.
wire        s_readonly = ready & (wp | !RWMODE);
reg			s_crcerr;
reg			s_headloaded, s_seekerr, s_index;  // mode 1
reg			s_lostdata, s_wrfault; 			     // mode 2,3

// Command mode 0/1 for status register
reg 			cmd_mode;

// allow write protect flag
reg 			s_wpe;

// DRQ/BUSY are always going together
reg	[1:0]	s_drq_busy;
wire			s_drq  = s_drq_busy[1];
wire			s_busy = s_drq_busy[0];
reg         s_intrq;

reg   [7:0] wdreg_track;
reg   [7:0] wdreg_sector;
reg   [7:0] wdreg_data;
// Type I status bit 5, head-engaged, is ALWAYS ZERO on this machine, and bit 4
// is the seek error alone -- not "seek error or not ready".
//
// Both come from 77AVEMU's shared FDC (`refs/TOWNSEMU/src/diskdrive/
// diskdrive.cpp:1213-1243`), and the first carries an experiment on real
// hardware in CaptainYS's own words: "Observation from real FM77AV tells that
// head-engaged flag will not be set even if head-load flag is set in the
// command. Murder Club checks head-engaged flag and if set, it fails to start."
// Its `SeekError()` returns false unconditionally (`:1372`), so bit 4 never
// sets either.
//
// This core reported both. Against the reference, the boot ROM's four-drive
// probe -- RESTORE on each of $fd1d = $80/$81/$82/$83 -- came back $24/$f4/$94/
// $94 here where 77AVEMU answers $44/$84/$84/$04: head-engaged on every drive,
// and a seek error on every EMPTY one, because `~ready` was folded into bit 4.
// An empty drive is not a seek failure, and software that probes drives before
// deciding what it can load reads the difference.
wire  [7:0] wdreg_status = cmd_mode == 0 ?
	{~ready, s_readonly & s_wpe, 1'b0,      s_seekerr, s_crcerr, !disk_track, s_index, s_busy}:
	{~ready, s_readonly & s_wpe, s_wrfault, s_seekerr, s_crcerr, s_lostdata,  s_drq,   s_busy};

reg   [7:0] read_addr[6];
reg   [7:0] q;
always @* begin
	case (addr)
		A_STATUS: q = wdreg_status;
		A_TRACK:  q = wdreg_track;
		A_SECTOR: q = wdreg_sector;
		A_DATA:   q = (state == STATE_IDLE) ? wdreg_data : buff_rd ? (RWMODE ? buff_dout : buff_din) : read_addr[byte_addr[2:0]];
	endcase
end

reg         buff_rd;
reg         step_direction; // last step direction

reg   [7:0] disk_track;		 // "real" heads position
reg  [10:0]	data_length;	 // this many bytes to transfer during read/write ops
io_state_t  state = STATE_IDLE;
`ifdef DEBUG_FDC_SCAN
// One line per change of the SECTOR register, whoever caused it. A bus trace
// cannot show this: if the controller alters the register internally the CPU
// never sees a write, and the next read-modify-write the loader does silently
// skips a sector. Pro Yakyuu Fan disk A loses exactly four that way.
reg [7:0] dbg_sec_d;
always @(posedge clk_sys) begin
  dbg_sec_d <= wdreg_sector;
  if (wdreg_sector !== dbg_sec_d)
    $display("SECREG %m $%02x -> $%02x  state=%0d", dbg_sec_d, wdreg_sector, state);
end
`endif

// Reusable expressions
wire  [7:0] next_track  = (din[6] ? din[5] : step_direction) ? disk_track - 1'd1 : disk_track + 1'd1;
wire [10:0]	next_length = data_length - 1'b1;

// Watchdog
reg         watchdog_set;
wire        watchdog_bark = (wd_timer == 0);
reg  [15:0] wd_timer;
always @(posedge clk_sys) begin
	if(ce) begin
		if(watchdog_set) wd_timer <= 4096;
			else if(wd_timer != 0) wd_timer <= wd_timer - 1'b1;
	end
end

always @(posedge clk_sys) begin
	integer cnt;
	if(ce) begin
		// INDEX free-runs, and is NOT qualified on `ready`.
		//
		// The original code left cnt at 0 with no disk present, and 0 < 100, so
		// INDEX read as permanently ASSERTED -- an empty drive claiming
		// something was spinning in it. That was a real bug. Gating the whole
		// pulse on `ready` fixed it by removing the pulse altogether, which is
		// the opposite error: 77AVEMU's FM77AVFDC overrides the base class's
		// always-false IndexHole() with a pure function of time --
		// `fm77avTime % INDEXHOLE_INTERVAL < INDEXHOLE_DURATION`, 200 ms for
		// 300 rpm (fm77avfdc.cpp:1114, fm77avfdc.h:24-25) -- with no reference
		// to media, motor or ready at all.
		//
		// It matters on cassette runs, where no disk is mounted and `ready` is
		// therefore never true. The FM-7 boot ROM polls $FD18 at $FEE9 waiting
		// on INDEX: the reference alternates $84/$86 there while this core read
		// a fixed $84 forty thousand times. Crash Ball is the title that fails
		// on it -- `Found: CRB` then `Device I/O Error`, on hardware and in
		// simulation, where the reference loads and plays the same image.
		//
		// Letting cnt free-run cannot bring back the stuck-at-0 case, because
		// it is never reset to 0.
		if(cnt) cnt <= cnt - 1;
			else cnt <= 35000;
		s_index <= (cnt < 100);
	end
end

// The ID field's CRC, as READ ADDRESS reports it.
//
// A .d77 does not store the two CRC bytes -- it stores a per-sector STATUS byte
// ($a0 = ID CRC error, $b0 = data CRC error), which is a different thing -- so
// they have to be computed, and both references do compute them. This used to
// return `read_addr[4] <= 0; read_addr[5] <= 0;` and that is invisible until a
// title CHECKS them, because the C/H/R/N in front of them were already right.
//
// Xanadu Scenario II (Disk D - Program) checks them. Its loader issues
// READ ADDRESS seventeen times around the track and reads the six-byte record
// each time; the CHRN matched the reference exactly and the CRC did not:
//
//   reference   00 01 01 03 ED 7E    00 01 02 03 B8 2D    00 01 03 03 8B 1C
//   this core   00 01 01 03 00 00    00 01 02 03 00 00    00 01 03 03 00 00
//
// A CRC is exactly the field a copy-protection routine wants, because it cannot
// be forged from an idealised layout. The title then fed a byte derived from it
// back to $FD1B and asked for a different sector than the reference did.
//
// Standard floppy ID CRC: CRC-16-CCITT, polynomial $1021, seeded $FFFF, taken
// over the three $A1 sync bytes and the $FE address mark and then the four CHRN
// bytes. The preamble is constant, so its result is folded in as ID_CRC_SEED
// rather than recomputed -- verified against the reference's own output above,
// all four records, before being written here.
localparam [15:0] ID_CRC_SEED = 16'hB230;   // CRC-16-CCITT of $A1 $A1 $A1 $FE

function [15:0] crc16_ccitt;
	input [15:0] crc;
	input  [7:0] data;
	integer i;
	begin
		crc16_ccitt = crc ^ {data, 8'd0};
		for (i = 0; i < 8; i = i + 1)
			crc16_ccitt = crc16_ccitt[15] ? ((crc16_ccitt << 1) ^ 16'h1021)
			                              :  (crc16_ccitt << 1);
	end
endfunction

wire [15:0] id_crc = crc16_ccitt(crc16_ccitt(crc16_ccitt(crc16_ccitt(
	                     ID_CRC_SEED, edsk_trackf), edsk_sidef), edsk_sector), edsk_sizecode);

wire        rde = rd & io_en;
wire        wre = wr & io_en;
always @(posedge clk_sys) begin
	reg old_wr, old_rd;

	reg [2:0] cur_addr;
	reg       read_data;
	reg       write_data;
	reg       rw_type;
	integer   wait_time;
	reg [3:0] read_timer;
	reg [9:0] seektimer;
	reg [7:0] ra_sector;
	reg       multisector;
	reg       sec_crc;              // the sector being read was dumped with a CRC error
	reg       write;
	reg [5:0] ack;
	reg       sd_busy;
	reg       old_mounted;
	reg [3:0] scan_state;
	reg [1:0] scan_cnt;
	reg [1:0] blk_max;
	// No `= 0` initialisers here, and that is not style. Verilator treats a
	// declaration initialiser on a block-scoped reg as a BLOCKING assignment,
	// so pairing one with the `<=` updates below is BLKANDNBLK -- a hard error
	// on Verilator 4.x, which `vsim/Makefile` deliberately still supports. Both
	// toolchains power these up to 0 anyway (Cyclone V registers, and
	// `--x-initial fast`), which is what the have_image gate below relies on.
	reg [2:0] old_disk_index;
	reg       have_image;

	if(RWMODE) begin
		old_mounted <= img_mounted;
		// A re-scan is what makes selecting a different sub-disk take effect,
		// and the mount edge is NOT enough on its own: changing the OSD option
		// moves disk_index without re-mounting the file, so without this the
		// drive would keep the sector table it built for the previous
		// sub-disk and the option would appear to do nothing at all.
		//
		// Treated exactly like a mount, because that is what it is from the
		// machine's point of view -- the medium in the drive has changed.
		//
		// Gated on have_image, and that is not belt-and-braces. old_disk_index
		// resets to 0 while disk_index may already be non-zero, so an ungated
		// compare fires on the very first clock -- before anything is mounted.
		// That scan runs against a zero-length image, ends immediately, and
		// leaves the drive with no sector table at all: selecting any sub-disk
		// but the first reported fmt=0 / bytes=0 and the title fell back to the
		// F-BASIC banner. The render alone could not tell that apart from "this
		// sub-disk does not boot", which is what it looks like.
		if(old_mounted && ~img_mounted) have_image <= 1;
		old_disk_index <= disk_index;
		if((old_mounted && ~img_mounted) ||
		   (have_image && (old_disk_index != disk_index))) begin
			if(EDSK) begin
				scan_active<= 1;
				scan_addr  <= 0;
				scan_state <= 0;
				scan_wr    <= 0;
				sd_block   <= 0;
			end
			disk_size <= img_size[20:0];
			size_id_r <= img_size_id;
			layout_r  <= layout;
		end
	end else begin
		scan_active <= input_active;
		scan_addr   <= input_addr;
		scan_wr     <= input_wr;
		if(scan_active & ~input_active) begin
			disk_size <= input_addr + 1'd1;
			layout_r  <= layout;
		end
	end

	if(reset & ~scan_active) begin
		read_data <= 0;
		write_data <= 0;
		multisector <= 0;
		step_direction <= 0;
		disk_track <= 0;
		wdreg_track <= 0;
		wdreg_sector <= 0;
		wdreg_data <= 0;
		data_length <= 0;
		byte_addr <=0;
		buff_rd <= 0;
		if(RWMODE) buff_wr <= 0;
		state <= STATE_IDLE;
		cmd_mode <= 0;
		s_wpe <= 1;
		{s_headloaded, s_seekerr, s_crcerr, s_intrq} <= 0;
		{s_wrfault, s_lostdata} <= 0;
		s_drq_busy <= 0;
		watchdog_set <= 0;
		seektimer <= 'h3FF;
		{ack, sd_wr, sd_rd, sd_busy} <= 0;
		ra_sector <= 1;
	end else if(ce) begin

		ack <= {ack[4:0], sd_ack};
		if(ack[5:4] == 'b01) {sd_rd,sd_wr} <= 0;
		if(ack[5:4] == 'b10) sd_busy <= 0;

		if(RWMODE & scan_active) begin
			if(scan_addr >= scan_limit) scan_active <= 0;
			else begin
				case(scan_state)
					0:	begin
							sd_rd   <= 1;
							sd_busy <= 1;
							scan_wr <= 0;
							scan_state <= 1;
						end
					1: if(!sd_busy) begin
							scan_wr    <= 1;
							scan_cnt   <= 1;
							scan_state <= 2;
						end
					2: begin
							scan_cnt <= scan_cnt + 1'd1;
							if(!scan_cnt) begin
								scan_wr <= ~scan_wr;
								if(scan_wr) begin
									scan_addr <= scan_addr + 1'b1;
									if(&scan_addr[8:0]) begin
										scan_active <= var_size;
										scan_state  <= 0;
									end
								end
							end
						end
				endcase
			end
		end

		old_wr <=wre;
		old_rd <=rde;

		if((!old_rd && rde) || (!old_wr && wre)) cur_addr <= addr;

		//Register read operations
		if(old_rd && !rde && (cur_addr == A_STATUS)) s_intrq <= 0;

		//end of data reading
		if(old_rd && !rde && (cur_addr == A_DATA)) read_data <=1;

		//end of data writing
		if(old_wr && !wre && (cur_addr == A_DATA)) write_data <=1;

		case (state)
			/* Idle state or buffer to host transfer */
			STATE_IDLE:; // do nothing

			STATE_SEARCH:
				begin
					// Not ready ends the command, but it is NOT a seek error --
					// see the status comment above. Bit 7 already says "not
					// ready"; adding bit 4 tells software the head failed to
					// find its track, which is a different and worse answer.
					if(!ready) begin
						state <= STATE_ENDCOMMAND;
					end else begin
						seektimer <= seektimer - 1'b1;
						if(!seektimer) begin
							byte_addr <= 0;
							if(var_size) begin
								if(~format) edsk_addr <= edsk_start;
								if(EDSK) spt_addr  <= (side ? spt_size>>1 : 8'd0) + disk_track;
								state     <= STATE_SEARCH_1;
							end else begin
								if(!wdreg_sector || (wdreg_sector > sectors_per_track)) begin
									if(~format) s_seekerr <= 1;
									state <= STATE_ENDCOMMAND;
								end else begin
									state <= rw_type ? STATE_WAIT_READ : STATE_READ;
								end
							end
						end
					end
				end
			STATE_SEARCH_1:
				begin
					// Type-II reads locate a sector under the current head, but the
					// ID cylinder must still agree with the WD track register.  The
					// reference FDC checks C unconditionally and only makes H
					// conditional on the command's side-compare bit.  Omitting C
					// makes a stale track register read whatever sector number happens
					// to be under the head; Daisenryaku uses that case deliberately.
					if(rw_type & (edsk_track == disk_track) &
									(edsk_trackf == wdreg_track) &
									 (edsk_side == side) &
									 (format | (edsk_sector == wdreg_sector))) begin
						// LOCAL ADDITION (FM-7_MiSTer): a .d77 records whether the
						// sector was read back with a bad CRC when the disk was
						// dumped. Report it, the way the drive would have. Titles
						// that check for a deliberately-unreadable sector as copy
						// protection need this to be true. Not on a write: that
						// replaces the data, and not while formatting.
						//
						// Reported when the sector's data has been read (the FDC
						// checks the CRC after the data field), and like a real
						// WD179x a multi-sector read stops there. Flagging it at
						// the ID instead poisoned reads that are force-interrupted
						// before the bad sector: the MZ-80B IPL reads 16 sectors and
						// stops, and DISK37 has a bad 17th sector on every track.
						sec_crc <= crc_report & ~write & ~format & (|edsk_crc);
`ifdef DEBUG_FDC_SCAN
						$display("WDMATCH want trk=%0d side=%0d sec=%0d -> entry trk=%0d side=%0d sec=%0d off=%0d",
									disk_track, side, wdreg_sector, edsk_track, edsk_side, edsk_sector, edsk_offset);
`endif
						state <= STATE_WAIT_READ;
					end
					else
					if(~rw_type & (edsk_track == disk_track) &
									  (edsk_side == side)) begin
						read_addr[0] <= edsk_trackf;
						read_addr[1] <= edsk_sidef;
						read_addr[2] <= edsk_sector;
						read_addr[3] <= edsk_sizecode;
						read_addr[4] <= id_crc[15:8];
						read_addr[5] <= id_crc[7:0];
						state        <= STATE_READ;
					end
					else
					if(edsk_next == edsk_start) begin
`ifdef DEBUG_FDC_SCAN
						$display("WDNOMATCH want trk=%0d side=%0d sec=%0d (wdreg_track=%0d rw_type=%0d edsk_size=%0d)",
									disk_track, side, wdreg_sector, wdreg_track, rw_type, edsk_size);
`endif
						if(~format) s_seekerr <= 1;
						state <= STATE_ENDCOMMAND;
					end
					else
					begin
						edsk_addr <= edsk_next;
					end
				end
			// read before write in case if sector not aligned or smaller than 512b
			STATE_WAIT_READ:
				begin
`ifdef DEBUG_FDC_READ
					$display("FDCSEC start: buff_a=%05x base=%0d sector_size=%0d blk_size=%0d",
					         buff_a, buff_a[8:0], sector_size, blk_size);
`endif
					data_length <= sector_size;
					byte_addr   <= buff_a[8:0];
					blk_max     <= blk_size;
					sd_block    <= 0;
					state       <= RWMODE ? STATE_WAIT_READ_1 : write ? STATE_WRITE : STATE_READ;
				end
			STATE_WAIT_READ_1:
				begin
					sd_busy <= 1;
					sd_rd   <= 1;
					state   <= STATE_WAIT_READ_2;
				end
			STATE_WAIT_READ_2:
				begin
					if(!sd_busy) begin
						sd_block <= sd_block + 1'd1;
						state <= write ? STATE_WRITE : STATE_READ;
						if(sd_block < blk_max) state <= STATE_WAIT_READ_1;
					end
				end

			STATE_READ:
				begin
					watchdog_set <= 1;
					read_timer <= 15;
					state <= STATE_READ_1;
				end
			STATE_READ_1:
				begin
					read_timer <= read_timer - 1'b1;
					if(!read_timer) begin
						read_data <= 0;
						watchdog_set <= 0;
						s_lostdata <= 0;
						s_drq_busy <= 2'b11;
						state <= STATE_READ_2;
					end
				end
			STATE_READ_2:
				begin
`ifdef DEBUG_FDC_READ
					// One line per byte handed to the CPU. `make DEBUG_FDC_READ=1`,
					// and touch this file first -- Verilator bakes +define+ in when
					// it runs, so a plain rebuild keeps the old defines and prints
					// nothing (docs/REFERENCE.md trap 3).
					if(read_data & s_drq)
						$display("FDCRD byte_addr=%0d buff_dout=%02x buff_a=%05x sd_block=%0d data_length=%0d",
						         byte_addr, buff_dout, buff_a, sd_block, data_length);
`endif
					if(watchdog_bark | (read_data & s_drq)) begin
						// reset drq until next byte is read, nothing is lost
						s_drq_busy <= 2'b01;
						s_lostdata <= watchdog_bark;

						// EVERY byte handed to the CPU passes THROUGH the Data
						// Register on a WD1793 -- it is the single path for read
						// and write data -- so when the command ends the register
						// holds the LAST BYTE READ. Both references model exactly
						// that: CSP `datareg = disk[drvreg]->sector[index]`
						// (mb8877.cpp:506, and :543 for READ ADDRESS) and 77AVEMU
						// `dataReg = state.data[state.dataReadPointer++]`
						// (fm77avfdc.cpp:851).
						//
						// This core never updated wdreg_data from the disk. It is
						// written only by a CPU store (A_DATA below), and the idle
						// readback at the top of this file returns it, so after a
						// completed read $FD1B gave back the last value WRITTEN
						// instead of the last byte READ.
						//
						// That is not cosmetic: the FM-7 boot ROM's seek helper
						// reads $FD1B at $FED3 and uses the value as a TRACK
						// NUMBER. On Luxsor disk 1 this core read $10 there and
						// seeked to track 16 where the reference seeks to track 4,
						// at read #143 of an otherwise byte-identical load -- it
						// renders the Telenet splash correctly and then never
						// loads its title screen.
						if(read_data & s_drq)
							wdreg_data <= buff_rd ? (RWMODE ? buff_dout : buff_din)
							                      : read_addr[byte_addr[2:0]];

						if(next_length == 0) begin
							// either read the next sector, or stop if this is track end
							if(sec_crc) begin
								s_crcerr <= 1;
								state <= STATE_ENDCOMMAND;
							end else if(multisector) begin
								wdreg_sector <= wdreg_sector + 1'b1;
								state <= STATE_SEARCH;
							end else begin
								state <= STATE_ENDCOMMAND;
							end
						end else begin
							byte_addr <= byte_addr + 1'd1;
							data_length <= next_length;
							state <= STATE_READ;
						end
					end
				end

			STATE_WAIT_WRITE:
				begin
					if(!ready) begin
						s_wrfault <= 1;
						state <= STATE_ENDCOMMAND;
					end else begin
						sd_block <= 0;
						state <= STATE_WAIT_WRITE_1;
					end
				end
			STATE_WAIT_WRITE_1:
				begin
					sd_busy <= 1;
					sd_wr   <= 1;
					state   <= STATE_WAIT_WRITE_2;
				end
			STATE_WAIT_WRITE_2:
				begin
					if(!sd_busy) begin
						sd_block <= sd_block + 1'd1;
						if(sd_block < blk_max) state <= STATE_WAIT_WRITE_1;
						else begin
							if(format && var_size && !edsk_next) begin
								state <= STATE_ENDCOMMAND;
							end else if(multisector) begin
								edsk_addr <= edsk_next;
								wdreg_sector <= wdreg_sector + 1'b1;
								state <= STATE_SEARCH;
							end else begin
								state <= STATE_ENDCOMMAND;
							end
						end
					end
				end
			STATE_WRITE:
				begin
					watchdog_set <= 1;
					read_timer <= 15;
					state <= STATE_WRITE_1;
				end
			STATE_WRITE_1:
				begin
					read_timer <= read_timer - 1'b1;
					if(!read_timer) begin
						write_data <= 0;
						watchdog_set <= 0;
						s_lostdata <= 0;
						s_drq_busy <= 2'b11;
						state <= STATE_WRITE_2;
					end
				end
			STATE_WRITE_2:
				begin
					if(watchdog_bark | (write_data & s_drq)) begin
						s_drq_busy <= 2'b01;
						s_lostdata <= watchdog_bark;

						if(!next_length) state <= STATE_WAIT_WRITE;
						else begin
							byte_addr <= byte_addr + 1'd1;
							data_length <= next_length;
							state <= STATE_WRITE;
						end
					end
				end

			// Abort current operation ($D0)
			STATE_ABORT:
				begin
					data_length <= 0;
					{s_wrfault,s_seekerr,s_crcerr,s_lostdata} <= 0;
					state <= STATE_ENDCOMMAND;
				end

			STATE_WAIT:
				begin
					wait_time <= 4000;
					state <= STATE_WAIT_2;
				end
			STATE_WAIT_2:
				begin
					// A command issued to an empty drive must still terminate and
					// raise INTRQ, or software polling $FD1F after probing an
					// empty slot waits for ever. But it reports NOT READY only:
					// 77AVEMU's SeekError() is unconditionally false
					// (refs/TOWNSEMU/src/diskdrive/diskdrive.cpp:1372), and the
					// boot ROM's four-drive probe expects $84 from an empty
					// drive, not $94. (The superseded claim here was that the
					// Fujitsu controller reports not-ready AND seek-error.)
					// An empty drive still runs out the busy period before it
					// terminates. It MUST still terminate and raise INTRQ -- that
					// is what the paragraph above is about -- but ending the
					// command on the same cycle it was issued is not how the
					// reference behaves, and the difference is visible: on the
					// boot ROM's four-drive probe Shounen Mike polls $FD1F and
					// 77AVEMU answers $3F ninety-nine times before the Restore
					// raises IRQ and it reads $7F, where this core answered $7F
					// immediately. Letting the timer run covers both: the status
					// still reports NOT READY, just not instantly.
					if(wait_time) wait_time <= wait_time - 1;
					else state <= STATE_ENDCOMMAND;
				end

			// End any command.
			STATE_ENDCOMMAND:
				begin
					format  <= 0;
					buff_rd <= 0;
					if(RWMODE) buff_wr <=0;
					state <= STATE_IDLE;
					s_drq_busy <= 2'b00;
					seektimer <= 'h3FF;
					s_intrq <= 1;
				end
		endcase

		/* Register write operations */
		if (!old_wr & wre) begin
			case (addr)
				A_COMMAND:
					begin
`ifdef DEBUG_FDC_SCAN
						$display("WDCMD %02x accepted=%0d", din, ((state == STATE_IDLE) | (din[7:4] == 'hD)));
`endif
						s_intrq <= 0;
						if((state == STATE_IDLE) | (din[7:4] == 'hD)) begin
							cmd_mode <= din[7];
							s_wpe    <= ~din[7];

							// Accepting a command CLEARS the error bits. The WD179x
							// resets status on a new command, and 77AVEMU cannot even
							// express a stale one -- MakeUpStatus() builds the byte
							// from live state every time it is asked
							// (refs/TOWNSEMU/src/diskdrive/diskdrive.cpp:1213).
							//
							// Here s_seekerr was cleared only by reset, by a Force
							// Interrupt, and inside some Type II/III branches. Nothing
							// on the Type I path cleared it, so one error stuck for
							// ever: Shounen Mike sets it with an out-of-range sector,
							// then loops `W $fd1b <- $10 / W $fd18 <- $18 / R $fd18 ->
							// $10` -- SEEK to track 16 with verify DISABLED, which
							// cannot fail a seek, answered with a seek error from a
							// previous command. It never escapes.
							//
							// Type II and III branches below still clear their own
							// flags; this makes the Type I path do it too, at the one
							// point every command passes through.
							{s_seekerr, s_crcerr} <= 0;
							case (din[7:4])
							'h0: 	// RESTORE
								begin
									// head load as specified, index, track0
									s_headloaded <= din[3];
									wdreg_track <= 0;
									disk_track <= 0;

									// some programs like it when FDC gets busy for a while
									s_drq_busy <= 2'b01;
									state <= STATE_WAIT;
								end
							'h1:	// SEEK
								begin
									// set real track to datareg
									disk_track <= wdreg_data;

									// LOCAL CHANGE (FM-7_MiSTer): and update the TRACK
									// REGISTER with it too. A real WD179x seeks by
									// stepping until the track register equals the data
									// register (MAME's wd_fdc.cpp:412 `main_state == SEEK
									// && track == data`, stepping with `track += ...` at
									// :439/:457), so when a SEEK finishes the two always
									// agree. This moved only the head, leaving the track
									// register stale, so software that seeks and then
									// reads $fd19 back saw the old track. RESTORE and STEP
									// here already maintain it; SEEK was the odd one out.
									wdreg_track <= wdreg_data;
									s_headloaded <= din[3];

									// get busy
									s_drq_busy <= 2'b01;
									state <= STATE_WAIT;
								end
							'h2,	// STEP
							'h3,	// STEP & UPDATE
							'h4,	// STEP-IN
							'h5,	// STEP-IN & UPDATE
							'h6,	// STEP-OUT
							'h7:	// STEP-OUT & UPDATE
								begin
									// if direction is specified, store it for the next time
									if (din[6] == 1) step_direction <= din[5]; // 0: forward/in

									// perform step
									disk_track <= next_track;

									// update TRACK register too if asked to
									if (din[4]) wdreg_track <= next_track;

									s_headloaded <= din[3];

									// some programs like it when FDC gets busy for a while
									s_drq_busy <= 2'b01;
									state <= STATE_WAIT;
								end
							'h8, 'h9, // READ SECTORS
							'hA, 'hB: // WRITE SECTORS
								begin
									// seek data
									// 5: 0: read, 1: write
									// 4: m: 0: one sector, 1: until the track ends
									// 3: S: SIDE
									// 2: E: some 15ms delay
									// 1: C: check side matching?
									// 0: 0

									s_drq_busy <= 2'b01;
									{s_wrfault,s_seekerr,s_crcerr,s_lostdata} <= 0;

									{write,buff_rd} <= din[5] ? 2'b10 : 2'b01;
									if(RWMODE) buff_wr <= din[5];

									if(din[6]) wdreg_sector <= 1;

									format      <= din[6];
									multisector <= din[4];
									rw_type     <= 1;
									write_data  <= 0;
									read_data   <= 0;
									edsk_start  <= 0;
									edsk_addr   <= 0;
									state       <= STATE_SEARCH;
									s_wpe       <= din[5];

									if(s_readonly & din[5]) begin
										s_wrfault <= 1;
										state <= STATE_WAIT;
									end
								end
							'hC:	// READ ADDRESS
								begin
									// track, side, sector, sector size code, 2-byte checksum (crc?)
									s_drq_busy <= 2'b01;
									{s_wrfault,s_seekerr,s_crcerr,s_lostdata} <= 0;

									{write,buff_rd} <= 0;
									if(RWMODE) buff_wr <=0;

									format      <= 0;
									multisector <= 0;
									rw_type     <= 0;
									read_data   <= 0;
									edsk_start  <= edsk_next;
									data_length <= 6;

									read_addr[0] <= disk_track;
									read_addr[1] <= {7'b0, side};
									read_addr[2] <= ra_sector;
									read_addr[3] <= wd_size_code;
									read_addr[4] <= 0;
									read_addr[5] <= 0;

									if(ra_sector >= sectors_per_track) ra_sector <= 1;
										else ra_sector <= ra_sector + 1'd1;
									state <= STATE_SEARCH;
								end
							'hD:	// FORCE INTERRUPT (type IV)
								begin
									// SharpMZ: interrupting a running Type II/III command keeps the Type II status
									// layout (datasheet); only an idle controller shows Type I status. The MZ-800
									// IPL ends its multi-sector read with $D8 and needs status 00, not TRACK0.
									cmd_mode <= (state != STATE_IDLE) ? cmd_mode : 1'b0;
									if(state != STATE_IDLE) state <= STATE_ABORT;
									else begin
										{s_wrfault,s_seekerr,s_crcerr,s_lostdata, s_drq_busy} <= 0;
										// ANY of I0-I3 raises INTRQ, not just I3.
										// On an IDLE controller this used to clear the
										// error bits and stop, so INTRQ was never raised
										// -- the command write above has already done
										// `s_intrq <= 0` and nothing set it again,
										// because only STATE_ENDCOMMAND does.
										//
										// CSP is explicit and is the primary authority
										// here: `// force interrupt if bit0-bit3 is high
										// / if(cmdreg & 0x0f) { set_irq(true); }`
										// (mb8877.cpp:1191 cmd_forceint). 77AVEMU agrees
										// and goes further -- FM77AVFDC::IOWrite raises
										// it for ANY $Dx, bits or no bits, and routes it
										// to MAIN_IRQ_SOURCE_FDC as well
										// (fdc/fm77avfdc.cpp:626-630).
										//
										// WHERE THEY DISAGREE, and which we follow: on a
										// bare $D0 (no I bits) CSP does NOT interrupt and
										// 77AVEMU does. We follow CSP, which is also what
										// the WD1793 datasheet specifies -- $D0 is
										// "terminate with no interrupt".
										//
										// Two titles found this, one bit apart. Xanadu
										// (Disk A) writes $D8 -- I3, interrupt
										// immediately -- at pc=$035D with the FDC idle
										// and polls $FD1F at $035F for b6; this core
										// answered $3F 2159554 times and never drew a
										// pixel. Xanadu Scenario II (Disk D) writes $D4
										// -- I2, interrupt on the next INDEX PULSE -- and
										// waits on an IRQ handler to set bit 6 of $001F,
										// spinning at $01b7 forever. `din[3]` fixed the
										// first and left the second: both machines' main
										// CPU I/O writes are identical for 37 writes,
										// ours stops dead on the $D4 and the reference
										// goes on to issue 3566 Read Address commands.
										//
										// The conditional sources are not modelled as
										// conditions -- I0 (not-ready to ready), I1
										// (ready to not-ready) and I2 (index pulse) all
										// interrupt at once here, as they do in both
										// references. The index pulse in particular is
										// only ever 200 ms away (s_index above), so the
										// difference is a latency no title has been
										// observed to depend on.
										//
										// Route through ENDCOMMAND rather than setting
										// s_intrq here, so the raise happens on the
										// following cycle and shares the one path that
										// ends a command.
										if(|din[3:0]) state <= STATE_ENDCOMMAND;
									end
								end
							'hF:  // WRITE TRACK
								begin
									s_wpe <= din[5];
									{s_wrfault,s_seekerr,s_crcerr,s_lostdata} <= 0;
									s_drq_busy <= 2'b01;
									state <= STATE_WAIT;
								end
							'hE:	// READ TRACK
								begin
									{s_wrfault,s_crcerr,s_lostdata} <= 0;
									s_seekerr  <= 1;
									s_drq_busy <= 2'b01;
									state <= STATE_WAIT;
								end
							endcase
						end
					end

				A_TRACK:  begin
					if (!s_busy) wdreg_track <= din;
`ifdef DEBUG_FDC_SCAN
					else $display("WDDROP TRACK  <- $%02x while BUSY", din);
`endif
				end
				A_SECTOR: begin
					// Software commonly primes the sector register while a
					// RESTORE/SEEK/STEP command is busy, then starts the read
					// command after the head settles.  The WD179x keeps the
					// register write in that interval; only data-transfer
					// commands must reject a write that would change the
					// address of an operation already in progress.
					if (!s_busy || (state == STATE_WAIT) || (state == STATE_WAIT_2))
						{ra_sector, wdreg_sector} <= {din,din};
`ifdef DEBUG_FDC_SCAN
					else $display("WDDROP SECTOR <- $%02x while BUSY (kept $%02x)", din, wdreg_sector);
`endif
				end
				A_DATA:   wdreg_data <= din;
			endcase
		end
	end
end

`ifdef DEBUG_FDC_SCAN
// sd_ack edge tracer. STATE_WAIT_READ_2 waits on sd_busy, and sd_busy clears
// only on the FALLING edge of sd_ack (ack[5:4] == 'b10 above), so a sd_ack that
// goes high and never comes back down stalls the controller with the command
// still open -- no DRQ, no INTRQ, and the CPU spinning on $fd1f. See P4-4.
reg sd_ack_dbg = 1'b0;
always @(posedge clk_sys) begin
	sd_ack_dbg <= sd_ack;
	if (sd_ack != sd_ack_dbg)
		$display("WDACK %b -> %b  state=%0d sd_rd=%b sd_wr=%b lba=%0d",
		         sd_ack_dbg, sd_ack, state, sd_rd, sd_wr, sd_lba);
end
`endif

`ifdef DEBUG_FDC_SCAN
// State-machine tracer. The CPU spinning on $fd1f with neither DRQ nor INTRQ
// means the controller stopped somewhere without ending the command; this shows
// which state it stopped in and whether it is waiting on the SD handshake.
io_state_t state_dbg = STATE_IDLE;
always @(posedge clk_sys) begin
	state_dbg <= state;
	if (state != state_dbg)
		$display("WDST %0d -> %0d  sd_rd=%b sd_ack=%b drq=%b busy=%b intrq=%b lba=%0d blk=%0d",
		         state_dbg, state, sd_rd, sd_ack, s_drq, s_busy, s_intrq, sd_lba, sd_block);
end
`endif

reg        scan_active = 0;
reg [20:0] scan_addr;
reg        scan_wr;

wire [1:0] edsk_sizecode;          // sector size: 0=128K, 1=256K, 2=512K, 3=1024K
// LOCAL ADDITION (FM-7_MiSTer): {ID CRC error, data CRC error} for this sector,
// from the .d77 per-sector status byte, or for EDSK from the FDC status bytes
// of the sector information block (ST1 bit 5 DE, ST2 bit 5 DD).
wire [1:0] edsk_crc;
wire       edsk_side;              // Side number (0 or 1)
wire [6:0] edsk_track;             // Track number
wire [7:0] edsk_sector;            // Sector number 0..15
wire[20:0] edsk_offset;
wire [7:0] edsk_trackf, edsk_sidef;

reg [11:0] edsk_addr, edsk_start;

reg [11:0] edsk_size = 0;
wire[11:0] edsk_next = ((edsk_addr + 1'd1) >= edsk_size) ? 12'd0 : edsk_addr + 1'd1;

reg  [7:0] spt_size = 0;

// LOCAL CHANGE (FM-7_MiSTer): spt_addr was declared inside the `generate
// if(EDSK)` block below, but it is assigned at line ~404 in an always block
// OUTSIDE that generate scope. Quartus tolerates this; Verilator rejects it
// with "Can't find definition of variable: 'spt_addr'". Moved to module scope,
// alongside spt_size which already lives here. No behavioural change.
reg  [7:0] spt_addr;
// Same problem, same fix: buff_wr was declared inside the `generate if(RWMODE)`
// block but is assigned from always blocks outside it (lines ~326/597/673/699).
reg        buff_wr;

// LOCAL ADDITION (FM-7_MiSTer): write-protect flag lifted out of the image
// header by the .d77 scanner. Driven from inside the EDSK generate block;
// with EDSK=0 nothing drives it and it stays 0, which is the safe default.
reg        d77_wp = 0;
assign     fmt_wp = d77_wp;

generate
	if(EDSK) begin
		wire [7:0] scan_data = RWMODE ? buff_dout : input_data;
		// The sector index has two independent producers (EDSK and D77), which
		// prevented Quartus 17 from inferring the old reg [55:0] edsk[1992] as
		// RAM. It became 111,552 flip-flops and made the design require 278% of
		// the device. Funnel both parsers through one registered write port and
		// use the core's explicit Cyclone V altsyncram wrapper.
		reg         edsk_wren = 0;
		reg  [11:0] edsk_wraddr;
		reg  [56:0] edsk_wrdata;
		wire [56:0] edsk_q;

		wd1793_mem #(
			.DATAWIDTH(57),
			.ADDRWIDTH(12),
			.NUMWORDS(4096)
		) edsk_ram (
			.clock     (clk_sys),
			.address_a (edsk_wraddr),
			.data_a    (edsk_wrdata),
			.wren_a    (edsk_wren),
			.q_a       (),
			.address_b (edsk_addr),
			.data_b    (57'd0),
			.wren_b    (1'b0),
			.q_b       (edsk_q)
		);

		assign {edsk_track,edsk_side,edsk_trackf,edsk_sidef,edsk_sector,
		        edsk_sizecode,edsk_crc,edsk_offset} = edsk_q;

		reg  [7:0] spt[166];

		always @(posedge clk_sys) begin
			edsk_spt <= spt[spt_addr];
		end

		reg  [7:0] tpos;
		reg  [7:0] tsize;
		reg  [7:0] tsizes[166];
		reg        tskip_wait;
		always @(posedge clk_sys) tsize <= tsizes[tpos];

		wire[127:0] edsk_sig = "EXTENDED CPC DSK";
		wire[127:0] sig_pos  = edsk_sig >> (8'd120-(scan_addr[7:0]<<3));

		//-------------------------------------------------------------------
		// LOCAL ADDITION (FM-7_MiSTer): .D77 / .D88 sector-container support
		//
		// .d77 is what FM-7 (and PC-88) software ships as. Unlike the fixed
		// geometries above it interleaves a 16-byte header BEFORE every
		// sector, so no amount of linear arithmetic over the file lands on
		// sector data -- a mount-time table is mandatory. The layout is
		// documented in refs/fdc/d77-format.md; briefly:
		//
		//   $00       17 bytes disk name
		//   $1a       write protect ($00 writable, $10 protected)
		//   $1b       media type ($00 = 2D, $10 = 2DD)
		//   $1c       4 bytes LE total image size == the file size
		//   $20       164 x 4 bytes LE track offset table, indexed
		//             track*2+side (side is the fast-varying index),
		//             0 = track absent
		//   then      per track: sector_count x (16-byte header + data),
		//             back to back, the count coming from the FIRST header
		//             of the track only
		//
		// This fills exactly the same edsk[]/spt[]/edsk_size/spt_size
		// structures the EDSK parser does, so the whole runtime path
		// (STATE_SEARCH_1, buff_a <= edsk_offset, ...) is reused untouched.
		//
		// Both parsers are pure forward byte-stream consumers: the driver at
		// the top of this file replays the image one byte at a time and never
		// seeks, so nothing here may look backwards.
		//-------------------------------------------------------------------
		localparam FMT_NONE = 2'd0;   // not recognised: fall back to size_code
		localparam FMT_EDSK = 2'd1;
		localparam FMT_D77  = 2'd2;

		// Compacted track table: {table index, byte offset} for present tracks
		// only, in the order they appear in the file. Zero entries are dropped
		// at build time so the second pass never has to skip over them.
		reg [27:0] d77_pres[164];
		reg  [7:0] d77_cnt = 0;      // how many entries are valid
		reg  [7:0] d77_rd  = 0;      // cursor: the track we are looking for
		reg [27:0] d77_q;
		always @(posedge clk_sys) d77_q <= d77_pres[d77_rd];
		wire  [7:0] d77_idx = d77_q[27:20];
		wire [19:0] d77_off = d77_q[19:0];

		always @(posedge clk_sys) begin
			reg old_active, old_wr;
			reg [13:0] hdr_pos, bcnt;
			reg  [7:0] idStatus;
			reg  [6:0] track;
			reg        side;
			reg  [7:0] sector;
			reg  [1:0] sizecode;
			reg  [7:0] crc1;
			reg  [7:0] crc2;
			reg  [7:0] sectors;
			reg [15:0] track_size, track_pos;
			reg [20:0] offset, offset1;
			reg  [7:0] size_lo;
			reg        st1_de;           // EDSK sector info: FDC status 1 bit 5 (data error)
			reg        st2_dd;           //                   FDC status 2 bit 5 (data error in the data field)
			reg [11:0] secpos;
			reg  [7:0] trackf, sidef;

			// .d77 parser state
			reg  [1:0] fmt;                    // which format we committed to
			reg        edsk_bad;               // signature mismatched somewhere
			reg [23:0] d_tot;                  // header $1c..$1e, total size LE
			reg [19:0] d_acc;                  // track table entry being built
			reg  [7:0] d_max;                  // highest present table index
			reg        d_wpb;                  // header $1a, before we commit
			reg  [1:0] d_st;                   // 0 seek track, 1 header, 2 data
			reg  [3:0] d_hpos;                 // byte within the 16-byte header
			reg        d_first;                // first header of this track
			reg [15:0] d_dlen;                 // data bytes still to skip
			reg  [7:0] d_left;                 // sectors still to come this track
			reg  [7:0] d_C, d_H, d_R;          // header +0..+2, as recorded
			reg  [1:0] d_N;                    // header +3, sector size code
			reg  [1:0] d_crc;                  // header +8, {ID CRC err, data CRC err}
			reg  [7:0] d_slo, d_llo;           // low halves of the 16-bit fields
			reg  [6:0] d_track;                // physical track, from the table
			reg        d_side;                 // physical side,  from the table
			reg  [7:0] clr_cnt;
			reg        clr_run;
			reg [19:0] d_base;                 // file offset of the selected disk
			reg  [2:0] skip_left;              // sub-disks still to step over

			// Every .d77 field below is an offset from the SELECTED disk's start,
			// not from the start of the file: the header, the track table and the
			// table's own entries are all disk-relative. The one exception is the
			// sector data address written into edsk[], which is what the runtime
			// hands to the SD reader and must stay absolute.
			reg [19:0] rel;
			reg [20:0] next_base;
			rel       = scan_addr - d_base;
			next_base = {1'b0, d_base} + {1'b0, d_tot[19:0]};

			old_active <= scan_active;
			edsk_wren <= 0;
`ifdef DEBUG_FDC_SCAN
			if(~scan_active & old_active)
				$display("D77SCAN done: fmt=%0d bytes=%0d tracks=%0d sectors=%0d spt_size=%0d wp=%0d",
							fmt, scan_addr, d77_cnt, edsk_size, spt_size, d77_wp);
`endif
			if(scan_active & ~old_active) begin
				edsk_size <=0;
				spt_size  <=0;
				track_pos <=0;
				var_size  <=1;

				fmt      <= FMT_NONE;
				edsk_bad <= 0;
				d_wpb    <= 0;
				d77_wp   <= 0;
				d77_cnt  <= 0;
				d77_rd   <= 0;
				d_max    <= 0;
				d_st     <= 0;
				clr_cnt  <= 0;
				clr_run  <= 1;
				d_base    <= 0;
				skip_left <= disk_index;
			end
			else if(clr_run) begin
				// Blank the sectors-per-track table so an absent track reads
				// back as 0 sectors rather than as whatever the last image
				// left there. 166 clk_sys cycles, and the first byte of the
				// image cannot arrive for at least a whole SD block read, so
				// this is always finished long before the parser starts.
				spt[clr_cnt] <= 0;
				clr_cnt <= clr_cnt + 1'd1;
				if(clr_cnt == 8'd165) clr_run <= 0;
			end

			old_wr <= scan_wr;

			// SharpMZ: step over unformatted (size 0) tracks in the EDSK track table between bytes;
			// the parser only advances while track_size is non-zero, so an image whose first track is
			// unformatted (e.g. only the MZ-800 boot track on side 1) was never parsed at all.
			// tsize follows tpos a clock later, hence one step every two clocks.
			tskip_wait <= 0;
			if(scan_active & (fmt == FMT_EDSK) & (scan_addr >= 256) & ~|track_size & (tpos < 8'd166) & ~tskip_wait & ~(scan_wr & ~old_wr)) begin
				track_size <= {tsize, 8'd0};
				track_pos  <= 0;
				tpos       <= tpos + 1'd1;
				tskip_wait <= 1;
			end

			if(scan_wr & ~old_wr & scan_active) begin

				//---------------------------------------------------------
				// Format detection, decided at byte $1f
				//
				// The original code cleared var_size on the first byte that
				// did not match the EDSK signature, which would kill a .d77
				// scan on byte 0 (a .d77 opens with a 17-byte disk name).
				// Accumulate instead, and commit once at $1f -- late enough
				// to have both the signature and the .d77 size field, early
				// enough that neither format's real content has started
				// (EDSK's fields begin at 48, .d77's track table at $20).
				//
				// .d77 has no magic number, so it is identified by its total
				// size field agreeing with the mounted image size.
				//
				// NOT exact equality: a .d77 may be a MULTI-DISK CONTAINER,
				// several images concatenated, where the header's size field
				// describes only the first. 28 images in the Neo Kobe set are
				// such containers (2x, 3x, 4x and 6x), and requiring equality
				// rejected every one of them outright -- fmt=0, no sector
				// table, no write-protect, the drive never becomes ready and
				// the title draws nothing. XANADU.D77 is 2495040 bytes with a
				// 415840-byte header field, exactly 6 disks; the reference
				// boots it and this core did not.
				//
				// The heuristic still has to reject a raw image, so keep the
				// other three guards (byte $1f zero, top nibble of the size
				// zero) and require the field to be at least one header long.
				//---------------------------------------------------------
				if(scan_addr < 16) begin
					if(sig_pos[7:0] != scan_data) edsk_bad <= 1;
				end
				if(rel == 20'h1a) d_wpb      <= |scan_data;
				if(rel == 20'h1c) d_tot[7:0] <= scan_data;
				if(rel == 20'h1d) d_tot[15:8]<= scan_data;
				if(rel == 20'h1e) d_tot[23:16]<=scan_data;
				if(rel == 20'h1f) begin
					if(!edsk_bad) fmt <= FMT_EDSK;
					else if(~|scan_data && ~|d_tot[23:20] &&
					        (d_tot[23:0] <= size_id_r) && (d_tot[19:0] >= 20'h2b0)) begin
						// This header is sound. If sub-disks remain to be
						// stepped over, move the base to the next one and keep
						// scanning WITHOUT committing -- the body below stays
						// gated on FMT_D77, so nothing is parsed meanwhile.
						//
						// The skip stops early rather than running off the end:
						// asking for disk 5 of a two-disk image leaves you on
						// the last one that exists instead of on no disk at
						// all, and a drive that never becomes ready is a much
						// worse answer than the wrong disk.
						// 21 bits on purpose. d_base and d_tot are both 20, and
						// their sum is not: XANADU.D77's disk 3 would start at
						// 831,680 + 415,840 = 1,247,520, which wraps to 198,944
						// in 20-bit arithmetic, sails through a "< 1 MB" test
						// and lands the parser in the middle of disk 0. The
						// clamp then reports fmt=0 and a drive that never
						// becomes ready, which reads as a container the scanner
						// cannot parse rather than as an out-of-range request.
						if(|skip_left && (next_base < {1'b0, scan_limit})) begin
							d_base    <= next_base[19:0];
							skip_left <= skip_left - 1'd1;
						end
						else begin
							fmt    <= FMT_D77;
							d77_wp <= d_wpb;
						end
					end
					else begin
						// Neither: stop the scan (the driver samples var_size
						// at each 512-byte boundary) and leave the runtime on
						// the fixed geometry selected by size_code.
						fmt      <= FMT_NONE;
						var_size <= 0;
					end
				end

				if(fmt == FMT_D77) begin
					if(rel < 20'h2b0) begin
						//-----------------------------------------------
						// $20..$2af -- 164 x 4-byte LE track offsets.
						// Present ones are appended to d77_pres in table
						// order, which is also the order they appear in
						// the file; absent ones (offset 0) are dropped.
						//-----------------------------------------------
						case(rel[1:0])
							0: d_acc[7:0]    <= scan_data;
							1: d_acc[15:8]   <= scan_data;
							2: d_acc[19:16]  <= scan_data[3:0];
							3: if(|d_acc && ~|scan_data && (d77_cnt < 8'd164)) begin
									d77_pres[d77_cnt] <= {rel[9:2] - 8'd8, d_acc};
									d77_cnt <= d77_cnt + 1'd1;
									d_max   <= rel[9:2] - 8'd8;
								end
						endcase
					end
					else begin
						//-----------------------------------------------
						// $2b0.. -- the sector records themselves
						//-----------------------------------------------

						// spt[] is indexed side*tracks + track, so it needs
						// the track count, which is only known once the
						// whole table has been read. d_max is the highest
						// present index = track*2+side, so tracks is
						// (d_max>>1)+1 and spt_size is twice that. Settled
						// here, five bytes before the first spt[] write.
						if(rel == 20'h2b0) spt_size <= {d_max[7:1], 1'b0} + 8'd2;

						//-----------------------------------------------
						// A track ENDS where the next present track begins,
						// whatever its header claimed. This test is hoisted
						// out of the state machine so it fires in the middle
						// of a header or of sector data too.
						//
						// Marchen Veil [b] is why. Its tracks 5/side 0 and
						// 32/side 1 declare nsec=256 while physically holding
						// ten sectors, with the order shuffled so sector 1 is
						// LAST -- ordinary FM-7 copy protection. Trusting the
						// count walked ~246 garbage headers and lost sync: the
						// image's declared sectors sum to 1320 and the scan
						// built 810, so 5/0/1 was never indexed and every read
						// of it returned RECORD NOT FOUND (status $10, 12156
						// times in 700 frames, a value the reference never
						// returns once).
						//
						// Bounding by extent is also the general answer: no
						// lying count can now walk off its own track.
						//-----------------------------------------------
						if((d77_rd < d77_cnt) && (rel == d77_off)) begin
							// this byte is header +0 of the track's first sector
							d_track <= d77_idx[7:1];
							d_side  <= d77_idx[0];
							d_C     <= scan_data;
							d_first <= 1;
							d_hpos  <= 1;
							d_st    <= 1;
							// step the cursor now; the value is not needed
							// again until this track ends, which is thousands
							// of cycles away.
							d77_rd  <= d77_rd + 1'd1;
						end
						else case(d_st)
							0: ; // between tracks: the hoisted test above starts one

							1: begin // 16-byte sector header
									d_hpos <= d_hpos + 1'd1;
									case(d_hpos)
										 0: d_C   <= scan_data;              // C
										 1: d_H   <= scan_data;              // H
										 2: d_R   <= scan_data;              // R
										 3: d_N   <= scan_data[1:0];         // N
										 4: d_slo <= scan_data;              // sectors LE lo
										 5: if(d_first) begin
												// Sector count for the whole track,
												// and only meaningful in the first
												// header. Some tools write $1000
												// where they meant $10.
												// A count that does not fit in 8 bits is a
												// lie (Marchen Veil declares 256). Taking
												// the low byte gave d_left = 0 -- one
												// sector read from the track -- and
												// spt = 0, which makes the guard at
												// `wdreg_sector > sectors_per_track` reject
												// EVERY sector number on it. Saturate
												// instead and let the extent bound above
												// end the track.
												// CAP the count at 32. No real floppy track
												// holds more; the densest FM-7 format is 26
												// sectors. Marchen Veil declares 256 on its
												// two protected tracks (5/side 0 and
												// 32/side 1) while physically holding ten
												// with the order shuffled so sector 1 is
												// LAST -- taking the low byte gave
												// d_left = 0, so ONE sector was read and
												// 5/0/1 was never indexed, and spt = 0 made
												// the `wdreg_sector > sectors_per_track`
												// guard reject every sector on the track.
												//
												// A cap, NOT a plausibility test on the
												// header. An earlier attempt ended the
												// track at the first header with H > 1,
												// which broke Thexder: its track 1 side 1
												// is a single sector with a deliberately
												// lying address mark (C=200 H=186 R=233),
												// and this scanner indexes such sectors on
												// purpose so READ ADDRESS can report the
												// lie. That guard cost 68 $fdxx cycles on
												// the gate's Thexder row.
												d_left <= ({scan_data, d_slo} == 16'h1000) ? 8'h10 :
															 (|scan_data | (d_slo > 8'd32))   ? 8'd32 :
															 (|d_slo)                         ? d_slo : 8'h01;
												spt[(d_side ? (spt_size >> 1) : 8'd0) + d_track] <=
															({scan_data, d_slo} == 16'h1000) ? 8'h10 :
															(|scan_data | (d_slo > 8'd32))   ? 8'd32 :
															(|d_slo)                         ? d_slo : 8'h01;
										end
										 8: begin
												// Status: $00 normal, $10 deleted but
												// valid, $a0 ID CRC error, $b0 data
												// CRC error, $e0/$f0 missing marks.
												// Only the two CRC cases have anywhere
												// to go in a WD179x status register.
												d_crc[1] <= (scan_data == 8'ha0);
												d_crc[0] <= (scan_data == 8'hb0);
										end
										14: d_llo <= scan_data;              // data length LE lo
										15: begin
												// The data length at +$0e is the real
												// byte count and is what we advance by;
												// it is NOT always consistent with N.
												d_dlen  <= {scan_data, d_llo};
												d_first <= 0;
												d_hpos  <= 0;

												// Emit the sector. Physical track/side
												// come from the table index, C/H from
												// the header, so a sector whose address
												// mark lies (copy protection) still gets
												// found by its physical position and
												// still reports the lie to READ ADDRESS.
												// Data begins at the very next byte.
												if(edsk_size < 12'd4000) begin
													edsk_wren   <= 1;
													edsk_wraddr <= edsk_size;
													edsk_wrdata <= {d_track, d_side, d_C, d_H, d_R, d_N, d_crc, scan_addr + 20'd1};
													edsk_size <= edsk_size + 1'd1;
`ifdef DEBUG_FDC_SCAN
													$display("D77SEC %0d %0d %0d %0d %0d %0d %0d %0d",
																d_track, d_side, d_C, d_H, d_R, d_N, scan_addr + 20'd1, d_crc);
`endif
												end
`ifdef DEBUG_FDC_SCAN
												else $display("D77SEC overflow at track %0d side %0d sector %0d", d_track, d_side, d_R);
`endif

												if(|{scan_data, d_llo}) d_st <= 2;
												else begin
													// zero-length sector: the next
													// header follows immediately
													d_left <= d_left - 1'd1;
													if(d_left <= 1) d_st <= 0;
												end
											end
										default:;
									endcase
								end

							2: begin // sector data, skipped a byte at a time
									d_dlen <= d_dlen - 1'd1;
									if(d_dlen <= 1) begin
										d_hpos <= 0;
										d_left <= d_left - 1'd1;
										// tracks are stored back to back, so the
										// next header starts at the next byte
										d_st   <= (d_left <= 1) ? 2'd0 : 2'd1;
									end
								end
						endcase
					end
				end

				if(fmt == FMT_EDSK) begin
					if( scan_addr == 48) spt_size <= scan_data; else
					if((scan_addr == 49) & (scan_data == 2)) spt_size <= spt_size << 1; else
					if( scan_addr == 52) begin
						track_size <= {scan_data, 8'd0};
						track_pos  <= 0;
						tpos <= 1;
					end else
					if((scan_addr  > 52) & (scan_addr < 218)) begin
						tsizes[scan_addr - 52] <= scan_data;
						spt[scan_addr - 52] <= 0;
					end else
					if((scan_addr >= 256) && track_size) begin
						track_pos <= track_pos + 1'd1;
						case(track_pos)
							00: offset  <= scan_addr + 9'd256;
							16: track   <= scan_data[6:0];
							17: side    <= scan_data[0];
							21: sectors <= scan_data;
							22: spt[(side ? (spt_size >> 1) : 8'd0) + track] <= sectors;
							default:
								if((track_pos >= 24) && sectors) begin
									case(track_pos[2:0])
										0: begin
												trackf  <= scan_data;
												secpos  <= edsk_size;
												offset1 <= offset;
											end
										1: sidef   <= scan_data;
										2: sector  <= scan_data;
										3: sizecode<= scan_data[1:0];
										4: st1_de  <= scan_data[5];
										5: st2_dd  <= scan_data[5];
										6: size_lo <= scan_data;
										7: begin
												if({scan_data, size_lo}) begin
													edsk_wren   <= 1;
													edsk_wraddr <= secpos;
													// The FDC status the sector was dumped with: a CRC error in the
													// data field (ST2 DD) or, without it, in the ID field (ST1 DE).
													edsk_wrdata <= {track,side,trackf,sidef,sector,sizecode,st1_de & ~st2_dd,st2_dd,offset1};
													edsk_size <= edsk_size + 1'd1;
													offset <= offset + {scan_data, size_lo};
												end
												sectors <= sectors - 1'd1;
											end
										default:;
									endcase
								end
						endcase
						if(track_pos >= (track_size - 1'd1)) begin
							track_size <= {tsize, 8'd0};
							track_pos  <= 0;
							tpos <= tpos + 1'd1;
						end
					end
				end
			end
		end
	end
endgenerate

endmodule

module wd1793_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=11)
(
	input	                     clock,

	input	     [ADDRWIDTH-1:0] address_a,
	input	     [DATAWIDTH-1:0] data_a,
	input	                     wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	     [ADDRWIDTH-1:0] address_b,
	input	     [DATAWIDTH-1:0] data_b,
	input	                     wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

logic [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always_ff@(posedge clock) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always_ff@(posedge clock) begin
	if(wren_b) begin
		ram[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b];
	end
end

endmodule
