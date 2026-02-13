module test_eeprom_tb (
    input wire clk,
    input wire rst,

    // eeprom_spi interface
    input  wire         eeprom_start,  // Pulse: start a transaction
    input  wire         eeprom_write,  // 1 = write byte, 0 = read byte
    input  wire [  6:0] eeprom_addr,   // EEPROM byte address (7 bits -> 128 bytes)
    input  wire [127:0] eeprom_wdata,  // Write data (ignored on read)
    output reg  [127:0] eeprom_rdata,  // Read data (valid when eeprom_done pulses)
    output reg          eeprom_done,   // Pulse: transaction complete
    output wire         eeprom_busy,   // High while a user transaction is in progress

    // SPI bus
    output wire spi_sclk,
    output wire spi_mosi,
    input  wire spi_miso,
    output wire cs_1,
    output wire cs_0
);
  // wires between u_eeprom_spi and u_spi_ctrl
  wire [255:0] spi_tx_data;
  wire [255:0] spi_rx_data;
  wire [5:0] spi_w_len;
  wire [5:0] spi_r_len;
  wire spi_cs_sel;

  wire spi_start;
  wire spi_done;
  wire spi_busy;

  eeprom_spi u_eeprom_spi (
      .clk(clk),
      .rst(rst),

      .eeprom_start(eeprom_start),
      .eeprom_write(eeprom_write),
      .eeprom_addr (eeprom_addr),
      .eeprom_wdata(eeprom_wdata),
      .eeprom_rdata(eeprom_rdata),
      .eeprom_busy (eeprom_busy),
      .eeprom_done (eeprom_done),

      .spi_start(spi_start),
      .spi_done (spi_done),
      .spi_busy (spi_busy),

      .spi_tx_data(spi_tx_data),
      .spi_rx_data(spi_rx_data),
      .spi_w_len  (spi_w_len),
      .spi_r_len  (spi_r_len),
      .spi_cs_sel (spi_cs_sel)
  );

  spi_ctrl u_spi_ctrl (
      .clk(clk),
      .rst(rst),

      // spi_ctrl interface
      .go  (spi_start),
      .done(spi_done),
      .busy(spi_busy),

      .cs_sel (spi_cs_sel),
      .tx_data(spi_tx_data),
      .rx_data(spi_rx_data),
      .w_len  (spi_w_len),
      .r_len  (spi_r_len),


      // spi out
      .sclk(spi_sclk),
      .mosi(spi_mosi),
      .miso(spi_miso),
      .cs0 (cs_0),
      .cs1 (cs_1)
  );

endmodule
