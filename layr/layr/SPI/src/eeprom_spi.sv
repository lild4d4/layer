
`ifndef SPI_REG_DEFINES
`define SPI_REG_DEFINES
`define SPI_REG_STATUS 32'h0000_0000
`define SPI_REG_CLKDIV 32'h0000_0002
`define SPI_REG_SPICMD 32'h0000_0004
`define SPI_REG_SPIADR 32'h0000_0006
`define SPI_REG_SPILEN 32'h0000_0008
`define SPI_REG_SPIDUM 32'h0000_000A
`define SPI_REG_TXFIFO 32'h0000_0010
`define SPI_REG_RXFIFO 32'h0000_0020
`endif

module eeprom_spi (
    input wire clk,
    input wire rst,

    // internal interface
    input wire eeprom_start,
    input wire eeprom_write,  // 1 = write, 0 read
    input wire [6:0] eeprom_addr,  // read / write address in eeprom
    input wire [127:0] eeprom_wdata,  // data to write to an address
    output reg [127:0] eeprom_rdata,  // data read from an address
    output reg eeprom_busy,
    output reg eeprom_done,

    // interface spi
    output reg spi_start,  // Issue start
    input  reg spi_done,
    input  reg spi_busy,

    input reg [255:0] spi_rx_data,  // Data received
    output reg [255:0] spi_tx_data,  // Data to Send
    output reg spi_cs_sel,  // 1 = eeprom, 0 = nfc
    output reg [5:0] spi_w_len,
    output reg [5:0] spi_r_len
);
  typedef enum logic [5:0] {
    S_IDLE,

    S_READ_0,
    S_READ_1,

    S_WRITE_CMD,
    S_DONE
  } state_t;

  reg [5:0] state;

  // Latched command
  reg       lat_write;
  reg [6:0] lat_addr;
  reg [7:0] lat_wdata;

  assign eeprom_busy = (state != S_IDLE);

  // AT25010B SPI opcodes
  localparam logic [7:0] OPWREN = 8'h06;
  localparam logic [7:0] OPRDSR = 8'h05;
  localparam logic [7:0] OPREAD = 8'h03;
  localparam logic [7:0] OPWRITE = 8'h02;


  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state        <= S_IDLE;
      lat_write    <= 1'b0;
      lat_addr     <= 7'h0;
      lat_wdata    <= 8'h0;
      eeprom_done  <= 1'b0;
      eeprom_rdata <= 8'h0;
      spi_start    <= 1'b0;
      spi_tx_data  <= 8'h0;
      spi_w_len    <= 5'd0;
      spi_r_len    <= 5'd0;
      spi_cs_sel   <= 1'b0;
    end else begin
      // auto-clear states
      eeprom_done <= 1'b0;
      spi_start   <= 1'b0;  // auto clear

      case (state)
        S_IDLE: begin
          if (eeprom_start) begin
            lat_write <= eeprom_write;
            lat_addr  <= eeprom_addr;
            lat_wdata <= eeprom_wdata;
            state     <= eeprom_write ? S_WRITE_CMD : S_READ_0;
          end
        end

        // READ sequence
        //
        // 1. set cs_1 low
        // 2. send OP (03h)
        // 3. send ADDR (1 byte)
        // 4. read (1 byte)
        // 5. set cs_1 high

        // pull cs_1, send read command
        S_READ_0: begin
          if (!spi_busy) begin
            spi_cs_sel <= 1'b1;
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
