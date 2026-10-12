// Simulation model of rtl/dprom.vhd: port A is read by the core, port B is
// the ioctl write port used to replace the contents (e.g. a new keymap).
// See dpram.v for timing and init_file handling.
module dprom #(
   parameter init_file     = "",
   parameter widthad_a     = 8,
   parameter width_a       = 8,
   parameter outdata_reg_a = "UNREGISTERED",
   parameter outdata_reg_b = "UNREGISTERED"
)(
   input      [widthad_a-1:0] address_a,
   input                      clock_a,
   input      [width_a-1:0]   data_a,
   input                      wren_a,
   output reg [width_a-1:0]   q_a,

   input      [widthad_a-1:0] address_b,
   input                      clock_b,
   input      [width_a-1:0]   data_b,
   input                      wren_b,
   output reg [width_a-1:0]   q_b
);
   localparam DEPTH = 1 << widthad_a;

   reg [width_a-1:0] mem [0:DEPTH-1] /*verilator public*/;

   integer i;
   initial begin
      for (i = 0; i < DEPTH; i = i + 1) mem[i] = {width_a{1'b0}};
      if (init_file != "") $readmemh({init_file, ".hex"}, mem);
   end

   always @(posedge clock_a) q_a <= mem[address_a];

   always @(posedge clock_b) begin
      if (wren_b) begin
         mem[address_b] <= data_b;
         q_b <= data_b;
      end else begin
         q_b <= mem[address_b];
      end
   end
endmodule
