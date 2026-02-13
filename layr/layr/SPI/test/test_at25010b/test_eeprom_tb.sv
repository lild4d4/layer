module test_eeprom_tb (
    input wire clk,
    input wire rst_n,

    // eeprom_spi interface
    input  wire       eeprom_start,  // Pulse: start a transaction
    input  wire       eeprom_write,  // 1 = write byte, 0 = read byte
    input  wire [6:0] eeprom_addr,   // EEPROM byte address (7 bits -> 128 bytes)
    input  wire [7:0] eeprom_wdata,  // Write data (ignored on read)
    output reg  [7:0] eeprom_rdata,  // Read data (valid when eeprom_done pulses)
    output reg        eeprom_done,   // Pulse: transaction complete
    output wire       eeprom_busy,   // High while a user transaction is in progress

    // SPI bus
    output wire spi_sclk,
    output wire spi_mosi,
    input  wire spi_miso,
    output wire cs_1
);
  // wires between u_eeprom_spi and u_spi
  wire [7:0] spi_data_in; // data received from eeprom
  wire [7:0] spi_data_out; // data to send from ASIC to eeprom

  wire spi_start;
  wire spi_done;
  wire spi_busy;
  

  eeprom_spi u_eeprom_spi (
      .clk  (clk),
      .rst_n(rst_n),

      .eeprom_start(eeprom_start),
      .eeprom_write(eeprom_write),
      .eeprom_addr(eeprom_addr),
      .eeprom_wdata(eeprom_wdata),
      .eeprom_rdata(eeprom_rdata),
      .eeprom_busy(eeprom_busy),
      .eeprom_done(eeprom_done),

      .spi_start(spi_start),
      .spi_data_in(spi_data_in),
      .spi_data_out(spi_data_out),
      .spi_done(spi_done),
      .spi_busy(spi_busy),
      .cs_1(cs_1)
  );

  spi_master u_spi (
      .clk  (clk),
      .reset(rst_n), // spi_master uses active-high reset

      .start   (spi_start),
      .data_in (spi_data_out),
      .data_out(spi_data_in),
      .done    (spi_done),
      .busy    (spi_busy),

      .miso(spi_miso),
      .mosi(spi_mosi),
      .sclk(spi_sclk)
  );

endmodule
