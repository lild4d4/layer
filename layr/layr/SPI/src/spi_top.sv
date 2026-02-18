module spi_top (
    input wire clk,
    input wire rst,

    // eeprom interface
    input wire eeprom_start,
    output wire eeprom_busy,
    output wire eeprom_done,
    input wire eeprom_get_key,  // get_key = 1, get_id = 0
    output wire [127:0] eeprom_rbuffer,

    // mfrc status outputs
    output wire        mfrc_ready,         // 1 = idle/ready
    output wire        mfrc_init_done,     // 1 = init complete
    output wire        mfrc_card_present,  // 1 = card detected
    output wire [15:0] mfrc_atqa,          // ATQA response

    // mfrc TX interface (to card)
    input  wire         mfrc_tx_valid,
    output wire         mfrc_tx_ready,
    input  wire [  4:0] mfrc_tx_len,
    input  wire [255:0] mfrc_tx_data,
    input  wire [  2:0] mfrc_tx_last_bits,

    // mfrc RX interface (from card)
    output wire         mfrc_rx_valid,
    output wire [  4:0] mfrc_rx_len,
    output wire [255:0] mfrc_rx_data,
    output wire [  2:0] mfrc_rx_last_bits,

    // spi bus output
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

      // status outputs
      .ready(mfrc_ready),
      .init_done(mfrc_init_done),
      .card_present(mfrc_card_present),
      .atqa(mfrc_atqa),

      // TX interface
      .tx_valid(mfrc_tx_valid),
      .tx_ready(mfrc_tx_ready),
      .tx_len(mfrc_tx_len),
      .tx_data(mfrc_tx_data),
      .tx_last_bits(mfrc_tx_last_bits),

      // RX interface
      .rx_valid(mfrc_rx_valid),
      .rx_len(mfrc_rx_len),
      .rx_data(mfrc_rx_data),
      .rx_last_bits(mfrc_rx_last_bits),

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

      // spi bus out
      .sclk(spi_sclk),
      .mosi(spi_mosi),
      .miso(spi_miso),
      .cs0 (cs_0),
      .cs1 (cs_1)
  );

endmodule
