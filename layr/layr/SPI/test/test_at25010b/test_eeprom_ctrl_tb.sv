module test_eeprom_ctrl_tb (
    input wire clk,
    input wire rst,

    // eeprom_spi interface
    (* MARK_DEBUG = "TRUE" *) input  wire         start,
    (* MARK_DEBUG = "TRUE" *) output reg          done,
    (* MARK_DEBUG = "TRUE" *) output wire         busy,
    (* MARK_DEBUG = "TRUE" *) input  wire         get_key,
                              output reg  [127:0] buffer,

    // SPI bus
    (* MARK_DEBUG = "TRUE" *) output wire spi_sclk,
    (* MARK_DEBUG = "TRUE" *) output wire spi_mosi,
    (* MARK_DEBUG = "TRUE" *) input  wire spi_miso,
    (* MARK_DEBUG = "TRUE" *) output wire cs_1,
    (* MARK_DEBUG = "TRUE" *) output wire cs_0
);
  // wires between u_eeprom_spi and u_spi_ctrl
  wire [255:0] spi_tx_data;
  wire [255:0] spi_rx_data;
  (* MARK_DEBUG = "TRUE" *) wire [5:0] spi_w_len;
  (* MARK_DEBUG = "TRUE" *) wire [5:0] spi_r_len;
  wire spi_cs_sel;

  (* MARK_DEBUG = "TRUE" *) wire spi_start;
  (* MARK_DEBUG = "TRUE" *) wire spi_done;
  (* MARK_DEBUG = "TRUE" *) wire spi_busy;

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
      .spi_r_len(spi_r_len)
  );

  spi_ctrl u_spi_ctrl (
      .clk(clk),
      .rst(rst),

      // spi_ctrl interface
      .go  (spi_start),
      .done(spi_done),
      .busy(spi_busy),

      .tx_data(spi_tx_data),
      .rx_data(spi_rx_data),
      .w_len  (spi_w_len),
      .r_len  (spi_r_len),

      .cs_sel(1),

      // spi out
      .sclk(spi_sclk),
      .mosi(spi_mosi),
      .miso(spi_miso),
      .cs0 (cs_0),
      .cs1 (cs_1)
  );

endmodule
