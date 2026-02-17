// spi_echo – sends one byte through spi_master, then performs a
// second transaction to read the slave's echo reply.
module spi_echo (
    input  wire       clk,
    input  wire       spi_clk_en, 
    input  wire       rst,      // active-high reset
    // Control interface
    input  wire       go,
    input  wire [7:0] tx_byte,
    output reg  [7:0] rx_byte,
    output reg        done,
    output reg        busy,
    // SPI bus
    output wire       sclk,
    output wire       mosi,
    input  wire       miso,
    output reg        ss
);
  reg  [7:0] spi_data_in;
  reg        spi_start;
  wire [7:0] spi_data_out;
  wire       spi_done;
  wire       spi_busy;

  // Store results due to slower cycle
  reg go_rec; 
  reg done_rec; 
  reg busy_rec;

  spi_master u_spi (
      .clk     (clk),
      .clk_en  (spi_clk_en),
      .reset   (rst),
      .data_in (spi_data_in),
      .start   (spi_start),
      .miso    (miso),
      .mosi    (mosi),
      .sclk    (sclk),
      .data_out(spi_data_out),
      .done    (spi_done),
      .busy    (spi_busy)
  );

  localparam S_IDLE       = 4'd0,
             S_TX_SETUP   = 4'd1,
             S_TX_START   = 4'd2,
             S_TX_WAIT    = 4'd3,
             S_TX_FINISH  = 4'd4,
             S_GAP        = 4'd5,
             S_RX_SETUP   = 4'd6,
             S_RX_START   = 4'd7,
             S_RX_WAIT    = 4'd8,
             S_RX_FINISH  = 4'd9,
             S_DONE       = 4'd10;

  reg [3:0] state;
  reg [7:0] gap_cnt;  // widened for longer waits

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state       <= S_IDLE;
      spi_data_in <= 8'd0;
      spi_start   <= 1'b0;
      ss          <= 1'b1;
      rx_byte     <= 8'd0;
      done        <= 1'b0;
      busy        <= 1'b0;
      gap_cnt     <= 8'd0;
      spi_start   <= 1'b0;
      go_rec      <= 1'b0;
      done_rec    <= 1'b0;
      busy_rec    <= 1'b0;
    end else begin
      done      <= 1'b0;
      if (go)
        go_rec <= go; 
      else if (spi_clk_en)
        go_rec <= 1'b0;

      if (spi_done)
        done_rec <= spi_done;
      else if (spi_clk_en)
        done_rec <= 1'b0;

      if (spi_busy)
        busy_rec <= spi_busy;
      else if (spi_clk_en)
        busy_rec <= 1'b0;

      if (spi_clk_en) begin
        spi_start <= 1'b0;

        case (state)
          S_IDLE: begin
            if (go_rec) begin
              busy        <= 1'b1;
              spi_data_in <= tx_byte;
              ss          <= 1'b0;  // assert SS
              gap_cnt     <= 8'd0;
              state       <= S_TX_SETUP;
            end
          end

          // ── give slave time after SS assert before first SCLK ──
          S_TX_SETUP: begin
            gap_cnt <= gap_cnt + 1;
            if (gap_cnt == 8'd3) begin
              state <= S_TX_START;
            end
          end

          S_TX_START: begin
            spi_start <= 1'b1;
            if(busy_rec)
              state     <= S_TX_WAIT;
          end

          S_TX_WAIT: begin
            if (done_rec) begin
              state <= S_TX_FINISH;
            end
          end

          // wait for master to go fully idle
          S_TX_FINISH: begin
            if (!spi_busy) begin
              ss      <= 1'b1;  // deassert SS
              gap_cnt <= 8'd0;
              state   <= S_GAP;
            end
          end

          // ── inter-transaction gap (SS high) ──
          S_GAP: begin
            gap_cnt <= gap_cnt + 1;
            if (gap_cnt == 8'd15) begin
              spi_data_in <= 8'h00;  // dummy TX
              ss          <= 1'b0;  // assert SS
              gap_cnt     <= 8'd0;
              state       <= S_RX_SETUP;
            end
          end

          // ── give slave time to drive MISO after SS assert ──
          S_RX_SETUP: begin
            gap_cnt <= gap_cnt + 1;
            if (gap_cnt == 8'd15) begin
              state <= S_RX_START;
            end
          end

          S_RX_START: begin
            spi_start <= 1'b1;
            if(busy_rec)
              state     <= S_RX_WAIT;
          end

          S_RX_WAIT: begin
            if (done_rec) begin
              rx_byte <= spi_data_out;
              state   <= S_RX_FINISH;
            end
          end

          // wait for master to go fully idle
          S_RX_FINISH: begin
            if (!busy_rec) begin
              state <= S_DONE;
            end
          end

          S_DONE: begin
            ss    <= 1'b1;
            done  <= 1'b1;
            busy  <= 1'b0;
            state <= S_IDLE;
          end

          default: state <= S_IDLE;
        endcase
      end
    end
  end
endmodule

