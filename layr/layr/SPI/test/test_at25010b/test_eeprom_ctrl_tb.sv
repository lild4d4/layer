module test_eeprom_ctrl_tb (
    input wire clk,
    input wire rst,

    // eeprom_spi interface
    input  wire         start,
    output reg          done,
    output wire         busy,
    input  wire         get_key,
    output reg  [127:0] buffer,

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

  eeprom_ctrl u_eeprom_ctrl (
      .clk(clk),
      .rst(rst),

      .start(start),
      .busy(busy),
      .done(done),
      .get_key(get_key),
      .buffer(buffer),

      .spi_start(spi_start),
      .spi_done(spi_done),
      .spi_busy(spi_busy),
      .spi_tx_data(spi_tx_data),
      .spi_rx_data(spi_rx_data),
      .spi_w_len(spi_w_len),
      .spi_r_len(spi_r_len),
      .spi_cs_sel(spi_cs_sel)
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
