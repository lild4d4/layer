module spi_master (
    input  wire       clk,       // System clock
    input  wire       reset,     // Reset signal (active high)
    // internal interface
    input  wire       start,     // Start signal (pulse for 1 clk)
    (* MARK_DEBUG = "TRUE" *) input  wire [7:0] data_in,   // Data to send
    output reg  [7:0] data_out,  // Data received
    output reg        done,      // Pulses high for 1 clk when byte is complete
    output reg        busy,      // High while a transfer is in progress
    // physical SPI wires
    input  wire       miso,      // Master In Slave Out
    output reg        mosi,      // Master Out Slave In
    output reg        sclk       // Serial Clock
);

  reg [2:0] bit_count;
  reg [7:0] shift_reg;
  reg [1:0] state;

  // SPI Mode 0: CPOL=0, CPHA=0
  //   - SCLK idles low
  //   - MOSI set up while SCLK is low
  //   - MISO sampled when SCLK goes high
  //
  // State machine (2 system clocks per SPI bit):
  //   State 0: Idle (SCLK=0)
  //   State 1: Setup  — SCLK=0, drive MOSI
  //   State 2: Capture — SCLK=1, sample MISO
  //   State 3: Finish — SCLK=0, return to idle

  localparam S_IDLE = 2'd0;
  localparam S_SETUP = 2'd1;
  localparam S_CAPTURE = 2'd2;
  localparam S_FINISH = 2'd3;

  always @(posedge clk or posedge reset) begin
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

      case (state)
        S_IDLE: begin
          sclk <= 1'b0;
          if (start) begin
            shift_reg <= data_in;
            bit_count <= 3'd0;
            busy      <= 1'b1;
            mosi      <= data_in[7];  // Drive first bit immediately
            state     <= S_CAPTURE;  // MOSI is set up, go to rising edge
          end
        end

        // SCLK low — drive MOSI for next bit
        S_SETUP: begin
          sclk  <= 1'b0;
          mosi  <= shift_reg[7];
          state <= S_CAPTURE;
        end

        // SCLK high — sample MISO
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

        // Return SCLK low, back to idle
        S_FINISH: begin
          sclk  <= 1'b0;
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule

