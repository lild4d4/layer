module chip(
    input clk,
    input rst,

    // SPI bus output (Pin13-17)
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso,
    output wire cs_0,  // Pin14 - cs_2 (MFRC522)
    output wire cs_1,  // Pin13 - cs_1 (AT25010B)

    // Status output (Pin20-22)
    output wire status_fault,
    output wire status_unlock,
    output wire status_busy
);

  wire layr_status;
  wire layr_status_valid;

  // Tie off EEPROM interface signals
  wire         eeprom_start;
  wire         eeprom_busy;
  wire         eeprom_done;
  wire         eeprom_get_key;
  wire [127:0] eeprom_rbuffer;

  assign eeprom_start   = 1'b0;
  assign eeprom_get_key = 1'b0;

  // Tie off MFRC interface signals
  wire         mfrc_tx_valid;
  wire         mfrc_tx_ready;
  wire [  4:0] mfrc_tx_len;
  wire [255:0] mfrc_tx_data;
  wire [  2:0] mfrc_tx_last_bits;

  wire         mfrc_rx_valid;
  wire [  4:0] mfrc_rx_len;
  wire [255:0] mfrc_rx_data;
  wire [  2:0] mfrc_rx_last_bits;

  wire         mfrc_card_present;

  // EEPROM interface (must be passed through unchanged)
  wire        auth_eeprom_busy   = eeprom_busy;
  wire        auth_eeprom_done   = eeprom_done;
  wire [127:0] auth_eeprom_buffer = eeprom_rbuffer;
  wire        auth_eeprom_start;       // driven by auth
  wire        auth_eeprom_get_key;     // driven by auth

  // results
  wire        unlocked;
  wire        forbidden;

  spi_top u_spi (
      .clk(clk),
      .rst(rst),

      // eeprom interface (tied off)
      .eeprom_start(eeprom_start),
      .eeprom_busy(eeprom_busy),
      .eeprom_done(eeprom_done),
      .eeprom_get_key(eeprom_get_key),
      .eeprom_rbuffer(eeprom_rbuffer),

      // mfrc interface (tied off)
      .mfrc_card_present(mfrc_card_present),
      .mfrc_tx_valid(mfrc_tx_valid),
      .mfrc_tx_ready(mfrc_tx_ready),
      .mfrc_tx_len(mfrc_tx_len),
      .mfrc_tx_data(mfrc_tx_data),
      .mfrc_tx_last_bits(mfrc_tx_last_bits),

      .mfrc_rx_valid(mfrc_rx_valid),
      .mfrc_rx_len(mfrc_rx_len),
      .mfrc_rx_data(mfrc_rx_data),
      .mfrc_rx_last_bits(mfrc_rx_last_bits),

      // SPI bus
      .spi_sclk(spi_sclk),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .cs_0(cs_0),
      .cs_1(cs_1)
  );

  layr layr(
      .clk               (clk),
      .rst               (rst),
      .busy              (status_busy),

      .card_present_i(mfrc_card_present),

      .mfrc_tx_valid(mfrc_tx_valid),
      .mfrc_tx_ready(mfrc_tx_ready),
      .mfrc_tx_len(mfrc_tx_len),
      .mfrc_tx_data(mfrc_tx_data),
      .mfrc_tx_last_bits(mfrc_tx_last_bits),

      .mfrc_rx_valid(mfrc_rx_valid),
      .mfrc_rx_len(mfrc_rx_len),
      .mfrc_rx_data(mfrc_rx_data),
      .mfrc_rx_last_bits(mfrc_rx_last_bits),

      // EEPROM interface (passed through)
      .eeprom_busy(auth_eeprom_busy),
      .eeprom_done(auth_eeprom_done),
      .eeprom_buffer(auth_eeprom_buffer),
      .eeprom_start(auth_eeprom_start),
      .eeprom_get_key(auth_eeprom_get_key),

      .status(layr_status),
      .status_valid(layr_status_valid)
  );

  assign status_unlock = unlocked;
  assign status_fault  = forbidden;
  
  always_ff @(posedge clk)begin
    if (rst)begin
        unlocked <= 0;
        forbidden <= 0;
    end else begin
      if(layr_status_valid)begin
        unlocked <= layr_status;
        forbidden <= ~layr_status;
      end
    end
  end
  

endmodule

