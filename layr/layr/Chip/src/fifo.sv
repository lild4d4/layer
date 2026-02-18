module sync_fifo #(parameter DEPTH=8, DWIDTH=16)
(
        input               	rst,
                            	clk,
                            	wr_en,
                            	rd_en,
        input      [DWIDTH-1:0] din,
        output reg [DWIDTH-1:0] dout,
        output              	empty,
                            	full
);
  reg [$clog2(DEPTH)-1:0]   wptr;
  reg [$clog2(DEPTH)-1:0]   rptr;

  reg [DWIDTH-1 : 0]    fifo[DEPTH];

  always @ (posedge clk) begin
    if (rst) begin
      wptr <= 0;
    end else begin
      if (wr_en & !full) begin
        fifo[wptr] <= din;
        wptr <= wptr + 1;
      end
    end
  end

  always @ (posedge clk) begin
    if (rst) begin
      rptr <= 0;
    end else begin
      if (rd_en & !empty) begin
        dout <= fifo[rptr];
        rptr <= rptr + 1;
      end
    end
  end

  assign full  = (wptr + 1) == rptr;
  assign empty = wptr == rptr;
endmodule