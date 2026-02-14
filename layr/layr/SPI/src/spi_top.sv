module spi_top (
    input wire clk,
    input wire reset,

    // eeprom interface
    input wire eeprom_start,
    output reg eeprom_busy,
    output reg eeprom_done,
    input wire eeprom_get_key,  // get_key = 1, get_id = 0
    output reg [127:0] eeprom_rbuffer,

    // mfrc interface
    // TBD

    // spi bus output
    // names according to challenge spec
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso,
    output reg cs_0,  // active-low chip select – MFRC522
    output reg cs_1  // active-low chip select – AT25010B
);

  eeprom_ctrl u_eeprom_ctrl (
      .clk(clk),
      .rst(rst),

      .start(eeprom_start),
      .busy(eeprom_busy),
      .done(eeprom_done),
      .get_key(eeprom_get_key),
      .buffer(eeprom_buffer),

      // connection to spi_arb
      .spi_start(e_spi_start),
      .spi_done(e_spi_done),
      .spi_busy(e_spi_busy),
      .spi_tx_data(e_spi_tx_data),
      .spi_rx_data(e_spi_rx_data),
      .spi_w_len(e_spi_w_len),
      .spi_r_len(e_spi_r_len),
      .spi_cs_sel(e_spi_cs_sel)
  );

  mfrc_top u_mfrc_top (
      .clk(clk),
      .rst(rst),

      // mfrc_core transceive API
      .trx_valid(),
      .trx_ready(),
      .trx_tx_len(),
      .trx_tx_data(),
      .trx_tx_last_bits(),
      .trx_timeout_cycles(),

      .trx_done(),
      .trx_ok(),
      .trx_rx_len(),
      .trx_rx_data(),
      .trx_rx_last_bits(),
      .trx_error(),

      // util API (VersionReg read)
      .ver_valid(),
      .ver_ready(),
      .ver_done(),
      .ver_ok(),
      .ver_value(),

      // connection to spi_arb
      .spi_go(m_spi_start),
      .spi_done(m_spi_done),
      .spi_busy(m_spi_busy),
      .spi_tx_data(m_spi_tx_data),
      .spi_rx_data(m_spi_rx_data),
      .spi_w_len(m_spi_w_len),
      .spi_r_len(m_spi_r_len),
      .spi_cs_sel(m_spi_cs_sel)
  );

  spi_arb u_spi_arb (
      .clk(clk),
      .rst(rst),

      // Client A (EEPROM)
      .a_go(e_spi_start),
      .a_wlen(e_spi_w_len),
      .a_rlen(e_spi_r_len),
      .a_tx_data(e_spi_tx_data),
      .a_done(e_spi_done),
      .a_rx_data(e_spi_rx_data),
      .a_busy(e_spi_busy),

      // Client B (MFRC)
      .b_go(m_spi_start),
      .b_wlen(m_spi_w_len),
      .b_rlen(m_spi_r_len),
      .b_tx_data(m_spi_tx_data),
      .b_done(m_spi_done),
      .b_rx_data(m_spi_rx_data),
      .b_busy(m_spi_busy),

      // spi bus out
      .sclk(spi_sclk),
      .mosi(spi_mosi),
      .miso(spi_miso),
      .cs0 (cs_0),
      .cs1 (cs_1)
  );

endmodule
