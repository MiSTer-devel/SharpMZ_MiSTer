`timescale 1ns/1ns
// mz_qdisk with a tape (.mzt) mounted: the stream that passes the head must be the disk tools/mzf2qdf.py makes
// of the same tape. run.sh builds the image hex and the expected stream, runs this and compares.
module tb;
   reg clk = 0;
   always #1 clk = ~clk;

   reg  [7:0] img[0:131071];
   integer    img_size;
   reg        img_mounted = 0;
   reg  [7:0] io_addr = 0, io_dout = 0;
   reg        io_wr = 0, io_rd = 0;
   wire [31:0] sd_lba;
   wire       sd_rd, sd_wr;
   reg        sd_ack = 0, sd_buff_wr = 0;
   reg  [8:0] sd_buff_addr = 0;
   reg  [7:0] sd_buff_dout = 0;
   wire [7:0] io_din, sd_buff_din;
   wire       io_oe, busy;

   mz_qdisk #(.BYTE_CLKS(40)) dut(
      .clk_sys(clk), .reset(1'b0), .enable(1'b1),
      .io_addr(io_addr), .io_rd(io_rd), .io_wr(io_wr), .io_dout(io_dout), .io_din(io_din), .io_oe(io_oe),
      .img_mounted(img_mounted), .img_readonly(1'b1), .img_size(img_size),
      .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
      .busy(busy));

   // hps_io's sector read: ack, 512 bytes, ack off.
   integer i;
   always @(posedge clk) if (sd_rd && !sd_ack) begin
      repeat (5) @(posedge clk);
      sd_ack <= 1;
      for (i = 0; i < 512; i = i + 1) begin
         @(posedge clk);
         sd_buff_addr <= i[8:0];
         sd_buff_dout <= (sd_lba * 512 + i < img_size) ? img[sd_lba * 512 + i] : 8'h00;
         sd_buff_wr   <= 1;
         @(posedge clk);
         sd_buff_wr   <= 0;
      end
      @(posedge clk);
      sd_ack <= 0;
   end

   task io_write(input [7:0] a, input [7:0] d);
      begin
         @(posedge clk); io_addr <= a; io_dout <= d; io_wr <= 1;
         @(posedge clk); io_wr <= 0;
         @(posedge clk);
      end
   endtask

   integer f, n, want, size_arg;
   initial begin
      $readmemh("out/img.hex", img);
      if (!$value$plusargs("size=%d", size_arg)) size_arg = 0;
      if (!$value$plusargs("bytes=%d", want)) want = 100000;
      img_size = size_arg;
      f = $fopen("out/stream.hex", "w");
      repeat (10) @(posedge clk);
      img_mounted <= 1; @(posedge clk); img_mounted <= 0;
      repeat (20000) @(posedge clk);                       // the scan
      io_write(8'hF7, 8'h05); io_write(8'hF7, 8'h80);       // WR5: motor on
      n = 0;
      while (n < want) begin
         @(posedge clk);
         if (dut.consume) begin $fwrite(f, "%02x\n", dut.next_byte); n = n + 1; end
      end
      $fclose(f);
      $display("files %0d, %0d bytes", dut.nfiles, n);
      $finish;
   end
endmodule
