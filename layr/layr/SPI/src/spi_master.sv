module spi_master (
    input  wire       clk,      // System clock
    input  wire       reset,    // Reset signal
    input  wire [7:0] data_in,  // Data to send
    input  wire       start,    // Start signal
    input  wire       miso,     // Master In Slave Out
    output reg        mosi,     // Master Out Slave In
    output reg        sclk,     // Serial Clock
    output reg        ss,       // Slave Select
    output reg  [7:0] data_out  // Data received
);

  reg [2:0] bit_count;  // Bit counter
  reg [7:0] shift_reg;  // Shift register for data transmission
  reg [1:0] state;  // State variable

  // State machine for SPI operation
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      ss        <= 1;  // Deactivate slave
      sclk      <= 0;  // Clock low
      bit_count <= 0;  // Reset bit counter
      state     <= 0;  // Idle state
    end else begin
      case (state)
        0: begin  // Idle state
          if (start) begin
            ss <= 0;  // Activate slave
            shift_reg <= data_in;  // Load data
            bit_count <= 0;  // Reset bit counter
            state <= 1;  // Move to next state
          end
        end
        1: begin  // Sending data
          mosi  <= shift_reg[7];  // Send MSB first
          sclk  <= 1;  // Clock high
          state <= 2;  // Move to next state
        end
        2: begin  // Clock Low: Shift data and increment
          sclk <= 0;
          shift_reg <= {shift_reg[6:0], 1'b0};
          // Increment here
          if (bit_count == 7) begin
            bit_count <= 0;  // Reset for the receive phase
            state <= 3;
          end else begin
            bit_count <= bit_count + 1;
            state <= 1;
          end
        end
        3: begin  // Receiving data
          data_out <= {data_out[6:0], miso};  // Shift in data
          if (bit_count == 7) begin
            ss <= 1;  // Deactivate slave
            state <= 0;  // Go back to idle
          end else begin
            bit_count <= bit_count + 1;  // Increment bit counter
            state <= 1;  // Continue sending
          end
        end
      endcase
    end
  end
endmodule




