module spi_master (
    input  wire       clk,
    input  wire       clk_en,    // clock enable (1 pulse per SPI clock period)
    input  wire       reset,
    input  wire       start,
    input  wire [7:0] data_in,
    output reg  [7:0] data_out,
    output reg        done,
    output reg        busy,
    input  wire       miso,
    output reg        mosi,
    output reg        sclk
);

  reg [2:0] bit_count;
  reg [7:0] shift_reg;
  reg [1:0] state;

  localparam S_IDLE    = 2'd0;
  localparam S_SETUP   = 2'd1;
  localparam S_CAPTURE = 2'd2;
  localparam S_FINISH  = 2'd3;

  always @(posedge clk) begin
    if (reset) begin
      sclk      <= 1'b0;
      mosi      <= 1'b0;
      bit_count <= 3'd0;
      shift_reg <= 8'd0;
      data_out  <= 8'd0;
      done      <= 1'b0;
      busy      <= 1'b0;
      state     <= S_IDLE;
    end else begin
      done <= 1'b0;

      if (clk_en) begin
        case (state)
          S_IDLE: begin
            sclk <= 1'b0;
            if (start) begin
              shift_reg <= data_in;
              bit_count <= 3'd0;
              busy      <= 1'b1;
              mosi      <= data_in[7];
              state     <= S_CAPTURE;
            end
          end
          S_SETUP: begin
            sclk  <= 1'b0;
            mosi  <= shift_reg[7];
            state <= S_CAPTURE;
          end
          S_CAPTURE: begin
            sclk      <= 1'b1;
            data_out  <= {data_out[6:0], miso};
            shift_reg <= {shift_reg[6:0], 1'b0};
            if (bit_count == 3'd7) begin
              done  <= 1'b1;
              busy  <= 1'b0;
              state <= S_FINISH;
            end else begin
              bit_count <= bit_count + 3'd1;
              state     <= S_SETUP;
            end
          end
          S_FINISH: begin
            sclk  <= 1'b0;
            state <= S_IDLE;
          end
        endcase
      end
    end
  end

endmodule