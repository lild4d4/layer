module eeprom_spi (
    input wire clk,
    input wire rst,

    // internal interface
    input wire eeprom_start,
    input wire [6:0] eeprom_addr,  // read / write address in eeprom
    output reg [127:0] eeprom_rdata,  // data read from an address
    output reg eeprom_busy,
    output reg eeprom_done,

    // interface spi
    output reg spi_start,  // Issue start
    input  reg spi_done,
    input  reg spi_busy,

    input  reg [255:0] spi_rx_data,  // Data received
    output reg [255:0] spi_tx_data,  // Data to Send
    output reg [  5:0] spi_w_len,
    output reg [  5:0] spi_r_len
);
  typedef enum logic [5:0] {
    S_IDLE,

    S_READ_0,
    S_READ_1
  } state_t;

  reg [5:0] state;

  // Latched addr
  reg [6:0] lat_addr;

  assign eeprom_busy = (state != S_IDLE);

  localparam logic [7:0] OPREAD = 8'h03;


  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state        <= S_IDLE;
      lat_addr     <= 7'h0;
      eeprom_done  <= 1'b0;
      eeprom_rdata <= 8'h0;
      spi_start    <= 1'b0;
      spi_tx_data  <= 256'h0;
      spi_w_len    <= 5'd0;
      spi_r_len    <= 5'd0;
    end else begin
      // auto-clear states
      eeprom_done <= 1'b0;
      spi_start   <= 1'b0;  // auto clear


      case (state)
        S_IDLE: begin
          spi_tx_data <= 256'h0;

          if (eeprom_start) begin
            lat_addr <= eeprom_addr;
            state    <= S_READ_0;
          end
        end

        // READ sequence
        //
        // 1. set cs_1 low, handled by spi_arb
        // 2. send OP (03h)
        // 3. send ADDR (1 byte)
        // 4. read (16 byte)
        // 5. set cs_1 high, hanlded by spi_arb

        // pull cs_1, send read command
        S_READ_0: begin
          if (!spi_busy) begin
            spi_w_len <= 5'd2;
            spi_r_len <= 5'd16;  // byte
            spi_tx_data[255:248] <= OPREAD;  // byte 0: opcode
            spi_tx_data[247:240] <= lat_addr;  // byte 1: address

            spi_start <= 1'b1;

            state <= S_READ_1;
          end
        end

        S_READ_1: begin
          if (spi_done) begin
            eeprom_rdata <= spi_rx_data[255:128];
            eeprom_done <= 1'b1;

            state <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
