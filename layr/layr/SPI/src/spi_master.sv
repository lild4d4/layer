module spi_master (
    input  wire       clk,      // System clock
    input  wire       reset,    // Reset signal
    input  wire [7:0] data_in,  // Data to send
    input  wire       start,    // Start signal (pulse for 1 clk)
    input  wire       miso,     // Master In Slave Out
    output reg        mosi,     // Master Out Slave In
    output reg        sclk,     // Serial Clock
    output reg  [7:0] data_out, // Data received
    output reg        done,     // Pulses high for 1 clk when byte is complete
    output reg        busy      // High while a transfer is in progress
);

  reg [2:0] bit_count;  // Bit counter
  reg [7:0] shift_reg;  // Shift register for data transmission
  reg [1:0] state;  // State variable

  // State machine for SPI operation
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      sclk      <= 0;  // Clock low
      mosi      <= 0;  // Master Out Slave In
      bit_count <= 0;  // Reset bit counter
      shift_reg <= 0;  // Shift register
      data_out  <= 0;  // Data received
      done      <= 0;
      busy      <= 0;
      state     <= 0;  // Idle state
    end else begin
      done <= 0;  // default: done is a single-cycle pulse

      case (state)
        0: begin  // Idle state
          if (start) begin
            shift_reg <= data_in;  // Load data to send
            bit_count <= 0;  // Reset bit counter
            busy      <= 1;
            state     <= 1;  // Move to setup phase
          end
        end
        1: begin  // Setup phase - put data on MOSI
          mosi <= shift_reg[7];  // Output MSB
          sclk <= 1;  // Clock high
          state <= 2;  // Move to capture phase
        end
        2: begin  // Capture phase - sample MISO and shift
          sclk <= 0;  // Clock low
          // Sample MISO on falling edge and shift into data_out
          data_out <= {data_out[6:0], miso};
          // Shift transmit data for next bit
          shift_reg <= {shift_reg[6:0], 1'b0};
          bit_count <= bit_count + 1;

          if (bit_count == 7) begin  // Last bit completed
            done  <= 1;
            busy  <= 0;
            state <= 0;  // Return to idle
          end else begin
            state <= 1;  // Continue with next bit
          end
        end
        default: state <= 0;
      endcase
    end
  end
endmodule




