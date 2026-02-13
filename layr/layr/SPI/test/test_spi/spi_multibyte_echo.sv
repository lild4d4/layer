module spi_multibyte_echo (
    input wire clk,
    input wire rst,  // active-high reset

    // Control interface
    input  wire go,
    output reg  done,
    output reg  busy,

    // RX data – read by testbench after done
    input  wire [3:0] rx_addr,
    output wire [7:0] rx_data,

    // SPI bus
    output wire sclk,
    output wire mosi,
    input  wire miso,
    output reg  ss
);

  // ── TX and RX buffers ──
  reg [7:0] tx_buf[0:15];
  reg [7:0] rx_buf[0:15];

  assign rx_data = rx_buf[rx_addr];

  // ── Initialize TX buffer with a deterministic pattern ──
  integer k;
  integer i;
  initial begin
    for (k = 0; k < 16; k = k + 1) tx_buf[k] = (k + 10) & 8'hFF;
  end

  // ── spi_master instance ──
  reg  [7:0] spi_data_in;
  reg        spi_start;
  wire [7:0] spi_data_out;
  wire       spi_done;
  wire       spi_busy;

  spi_master u_spi (
      .clk     (clk),
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

  // ── state machine ──
  localparam S_IDLE = 4'd0, S_TX_SS = 4'd1,  // assert SS, load first byte
  S_TX_SETUP = 4'd2,  // wait for slave setup after SS assert
  S_TX_START = 4'd3,  // pulse spi_start
  S_TX_WAIT = 4'd4,  // wait for spi_done
  S_TX_FINISH = 4'd5,  // wait for !spi_busy before deassert
  S_GAP = 4'd6,  // inter-frame gap (SS high)
  S_RX_SS = 4'd7,  // assert SS, load dummy byte
  S_RX_SETUP = 4'd8,  // wait for slave setup after SS assert
  S_RX_START = 4'd9,  // pulse spi_start
  S_RX_WAIT = 4'd10,  // wait for spi_done, store rx
  S_RX_FINISH = 4'd11,  // wait for !spi_busy before deassert
  S_DONE = 4'd12;

  reg [3:0] state;
  reg [3:0] byte_idx;
  reg [7:0] gap_cnt;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state       <= S_IDLE;
      spi_data_in <= 8'd0;
      spi_start   <= 1'b0;
      ss          <= 1'b1;
      done        <= 1'b0;
      busy        <= 1'b0;
      byte_idx    <= 4'd0;
      gap_cnt     <= 8'd0;
      for (i = 0; i < 16; i = i + 1) rx_buf[i] <= 8'd0;
    end else begin
      spi_start <= 1'b0;
      done      <= 1'b0;

      case (state)
        // ────────────────────────────────────────────
        S_IDLE: begin
          if (go) begin
            busy     <= 1'b1;
            byte_idx <= 4'd0;
            state    <= S_TX_SS;
          end
        end

        // ── TX frame: 16 bytes under one SS assertion ──
        S_TX_SS: begin
          ss          <= 1'b0;  // assert SS
          spi_data_in <= tx_buf[byte_idx];
          gap_cnt     <= 8'd0;
          state       <= S_TX_SETUP;
        end

        // give slave time after SS assert before first SCLK
        S_TX_SETUP: begin
          gap_cnt <= gap_cnt + 1;
          if (gap_cnt == 8'd3) begin
            state <= S_TX_START;
          end
        end

        S_TX_START: begin
          spi_start <= 1'b1;
          state     <= S_TX_WAIT;
        end

        S_TX_WAIT: begin
          if (spi_done) begin
            if (byte_idx == 4'd15) begin
              // all 16 bytes sent — wait for master to idle
              byte_idx <= 4'd0;
              state    <= S_TX_FINISH;
            end else begin
              // next byte (SS stays low)
              byte_idx    <= byte_idx + 1;
              spi_data_in <= tx_buf[byte_idx+1];
              state       <= S_TX_START;
            end
          end
        end

        // wait for spi_master to fully idle before deasserting SS
        S_TX_FINISH: begin
          if (!spi_busy) begin
            ss      <= 1'b1;  // deassert SS
            gap_cnt <= 8'd0;
            state   <= S_GAP;
          end
        end

        // ── inter-frame gap (SS high) ──
        S_GAP: begin
          gap_cnt <= gap_cnt + 1;
          if (gap_cnt == 8'd15) begin
            state <= S_RX_SS;
          end
        end

        // ── RX frame: 16 bytes under one SS assertion ──
        S_RX_SS: begin
          ss          <= 1'b0;  // assert SS
          spi_data_in <= 8'h00;  // dummy TX
          gap_cnt     <= 8'd0;
          state       <= S_RX_SETUP;
        end

        // give slave time to drive MISO after SS assert
        S_RX_SETUP: begin
          gap_cnt <= gap_cnt + 1;
          if (gap_cnt == 8'd15) begin
            state <= S_RX_START;
          end
        end

        S_RX_START: begin
          spi_start <= 1'b1;
          state     <= S_RX_WAIT;
        end

        S_RX_WAIT: begin
          if (spi_done) begin
            rx_buf[byte_idx] <= spi_data_out;
            if (byte_idx == 4'd15) begin
              // all 16 bytes received — wait for master to idle
              state <= S_RX_FINISH;
            end else begin
              byte_idx    <= byte_idx + 1;
              spi_data_in <= 8'h00;
              state       <= S_RX_START;
            end
          end
        end

        // wait for spi_master to fully idle before deasserting SS
        S_RX_FINISH: begin
          if (!spi_busy) begin
            state <= S_DONE;
          end
        end

        S_DONE: begin
          ss    <= 1'b1;  // deassert SS
          done  <= 1'b1;
          busy  <= 1'b0;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule

