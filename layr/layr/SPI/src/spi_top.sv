module spi_top (
    input wire clk,
    input wire rst,

    // eeprom interface
    input wire eeprom_start,
    output wire eeprom_busy,
    output wire eeprom_done,
    input wire eeprom_get_key,  // get_key = 1, get_id = 0
    output wire [127:0] eeprom_rbuffer,

    // mfrc interface
    input  wire         mfrc_trx_valid,
    output wire         mfrc_trx_ready,
    input  wire [  4:0] mfrc_trx_tx_len,
    input  wire [255:0] mfrc_trx_tx_data,
    input  wire [  2:0] mfrc_trx_tx_last_bits,
    input  wire [ 31:0] mfrc_trx_timeout_cycles,
    output wire         mfrc_trx_done,
    output wire         mfrc_trx_ok,
    output wire [  4:0] mfrc_trx_rx_len,
    output wire [255:0] mfrc_trx_rx_data,
    output wire [  2:0] mfrc_trx_rx_last_bits,
    output wire [  7:0] mfrc_trx_error,

    input  wire       mfrc_ver_valid,
    output wire       mfrc_ver_ready,
    output wire       mfrc_ver_done,
    output wire       mfrc_ver_ok,
    output wire [7:0] mfrc_ver_value,

    // spi bus output
    // names according to challenge spec
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso,
    output wire cs_0,  // active-low chip select – MFRC522
    output wire cs_1  // active-low chip select – AT25010B
);

  wire e_spi_go;
  wire [255:0] e_spi_tx_data;
  wire [255:0] e_spi_rx_data;
  wire [5:0] e_spi_w_len;
  wire [5:0] e_spi_r_len;
  wire e_spi_done;
  wire e_spi_busy;

  wire m_spi_go;
  wire [255:0] m_spi_tx_data;
  wire [255:0] m_spi_rx_data;
  wire [5:0] m_spi_w_len;
  wire [5:0] m_spi_r_len;
  wire m_spi_done;
  wire m_spi_busy;

  eeprom_ctrl u_eeprom_ctrl (
      .clk(clk),
      .rst(rst),

      .start(eeprom_start),
      .busy(eeprom_busy),
      .done(eeprom_done),
      .get_key(eeprom_get_key),
      .buffer(eeprom_rbuffer),

      // connection to spi_arb (Client A)
      .spi_start(e_spi_go),
      .spi_done(e_spi_done),
      .spi_busy(e_spi_busy),
      .spi_tx_data(e_spi_tx_data),
      .spi_rx_data(e_spi_rx_data),
      .spi_w_len(e_spi_w_len),
      .spi_r_len(e_spi_r_len)
  );

  mfrc_top u_mfrc_top (
      .clk(clk),
      .rst(rst),

      // mfrc_core transceive API
      .trx_valid(mfrc_trx_valid),
      .trx_ready(mfrc_trx_ready),
      .trx_tx_len(mfrc_trx_tx_len),
      .trx_tx_data(mfrc_trx_tx_data),
      .trx_tx_last_bits(mfrc_trx_tx_last_bits),
      .trx_timeout_cycles(mfrc_trx_timeout_cycles),

      .trx_done(mfrc_trx_done),
      .trx_ok(mfrc_trx_ok),
      .trx_rx_len(mfrc_trx_rx_len),
      .trx_rx_data(mfrc_trx_rx_data),
      .trx_rx_last_bits(mfrc_trx_rx_last_bits),
      .trx_error(mfrc_trx_error),

      // util API (VersionReg read)
      .ver_valid(mfrc_ver_valid),
      .ver_ready(mfrc_ver_ready),
      .ver_done(mfrc_ver_done),
      .ver_ok(mfrc_ver_ok),
      .ver_value(mfrc_ver_value),

      // connection to spi_arb (Client B)
      .spi_go(m_spi_go),
      .spi_done(m_spi_done),
      .spi_busy(m_spi_busy),
      .spi_tx_data(m_spi_tx_data),
      .spi_rx_data(m_spi_rx_data),
      .spi_w_len(m_spi_w_len),
      .spi_r_len(m_spi_r_len)
  );

  spi_arb u_spi_arb (
      .clk(clk),
      .rst(rst),

      // Client A (EEPROM)
      .a_go(e_spi_go),
      .a_wlen(e_spi_w_len),
      .a_rlen(e_spi_r_len),
      .a_tx_data(e_spi_tx_data),
      .a_done(e_spi_done),
      .a_rx_data(e_spi_rx_data),
      .a_busy(e_spi_busy),

      // Client B (MFRC)
      .b_go(m_spi_go),
      .b_wlen(m_spi_w_len),
      .b_rlen(m_spi_r_len),
      .b_tx_data(m_spi_tx_data),
      .b_done(m_spi_done),
      .b_rx_data(m_spi_rx_data),
      .b_busy(m_spi_busy),


      // // Client A (MFRC)
      // .a_go(m_spi_go),
      // .a_wlen(m_spi_w_len),
      // .a_rlen(m_spi_r_len),
      // .a_tx_data(m_spi_tx_data),
      // .a_done(m_spi_done),
      // .a_rx_data(m_spi_rx_data),
      // .a_busy(m_spi_busy),
      //
      // // Client B (EEPROM)
      // .b_go(e_spi_go),
      // .b_wlen(e_spi_w_len),
      // .b_rlen(e_spi_r_len),
      // .b_tx_data(e_spi_tx_data),
      // .b_done(e_spi_done),
      // .b_rx_data(e_spi_rx_data),
      // .b_busy(e_spi_busy),

      // spi bus out
      .sclk(spi_sclk),
      .mosi(spi_mosi),
      .miso(spi_miso),
      .cs0 (cs_0),
      .cs1 (cs_1)
  );

endmodule
