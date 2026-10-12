// Simulation model of rtl/dpram.vhd (an altsyncram BIDIR_DUAL_PORT wrapper).
//
// ghdl synth leaves dpram as a black box; this module fills it. Behaviour
// follows the altsyncram settings used by the core: unregistered outputs
// (q is valid the cycle after the address is clocked in), clock enables gate
// the input registers, and a write returns the new data on its own port.
//
// Port B may be wider than port A (VRAM0 is 8-bit on A, 16-bit on B). Like
// altsyncram, the lowest A address of a wide word sits in its least
// significant bits.
//
// init_file names a .mif; the Makefile converts each one to <name>.hex next
// to it for $readmemh.
module dpram #(
   parameter init_file     = "",
   parameter widthad_a     = 8,
   parameter width_a       = 8,
   parameter widthad_b     = 8,
   parameter width_b       = 8,
   parameter outdata_reg_a = "UNREGISTERED",
   parameter outdata_reg_b = "UNREGISTERED"
)(
   input                      clock_a,
   input                      clocken_a,
   input      [widthad_a-1:0] address_a,
   input      [width_a-1:0]   data_a,
   input                      wren_a,
   output reg [width_a-1:0]   q_a,

   input                      clock_b,
   input                      clocken_b,
   input      [widthad_b-1:0] address_b,
   input      [width_b-1:0]   data_b,
   input                      wren_b,
   output reg [width_b-1:0]   q_b
);
   localparam RATIO = width_b / width_a;
   localparam DEPTH = 1 << widthad_a;

   reg [width_a-1:0] mem [0:DEPTH-1] /*verilator public*/;

   integer i;
   initial begin
      for (i = 0; i < DEPTH; i = i + 1) mem[i] = {width_a{1'b0}};
      if (init_file != "") $readmemh({init_file, ".hex"}, mem);
   end

   always @(posedge clock_a) begin
      if (clocken_a) begin
         if (wren_a) begin
            mem[address_a] <= data_a;
            q_a <= data_a;
         end else begin
            q_a <= mem[address_a];
         end
      end
   end

   integer k;
   always @(posedge clock_b) begin
      if (clocken_b) begin
         for (k = 0; k < RATIO; k = k + 1) begin
            if (wren_b) begin
               mem[address_b * RATIO + k] <= data_b[k*width_a +: width_a];
               q_b[k*width_a +: width_a] <= data_b[k*width_a +: width_a];
            end else begin
               q_b[k*width_a +: width_a] <= mem[address_b * RATIO + k];
            end
         end
      end
   end
endmodule
