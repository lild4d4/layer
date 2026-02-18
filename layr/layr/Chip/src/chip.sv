module chip(
    input clk,
    input rst,
    input button,

    // SPI bus output (Pin13-17)
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso,
    output wire cs_0,  // Pin14 - cs_2 (MFRC522)
    output wire cs_1,  // Pin13 - cs_1 (AT25010B)

    // Status output (Pin23)
    output wire status_busy
);

  // Tie off EEPROM interface signals
  wire         eeprom_start;
  wire         eeprom_busy;
  wire         eeprom_done;
  wire         eeprom_get_key;
  wire [127:0] eeprom_rbuffer;

  assign eeprom_start   = 1'b0;
  assign eeprom_get_key = 1'b0;

  // Tie off MFRC interface signals
  wire         mfrc_trx_valid;
  wire         mfrc_trx_ready;
  wire [  4:0] mfrc_trx_tx_len;
  wire [255:0] mfrc_trx_tx_data;
  wire [  2:0] mfrc_trx_tx_last_bits;
  wire [ 31:0] mfrc_trx_timeout_cycles;
  wire         mfrc_trx_done;
  wire         mfrc_trx_ok;
  wire [  4:0] mfrc_trx_rx_len;
  wire [255:0] mfrc_trx_rx_data;
  wire [  2:0] mfrc_trx_rx_last_bits;
  wire [  7:0] mfrc_trx_error;

  assign mfrc_trx_valid = 1'b0;
  assign mfrc_trx_tx_len = 5'b0;
  assign mfrc_trx_tx_data = 256'b0;
  assign mfrc_trx_tx_last_bits = 3'b0;
  assign mfrc_trx_timeout_cycles = 32'b0;

  // ------------------------------------------------------------------
  //  Dummy signals for the auth module (tied‑off / looped‑back)
  // ------------------------------------------------------------------
  // Control signals
  wire        auth_operation_i = 1'b0;   // 0 = generate challenge
  wire        auth_start_i     = 1'b0;   // keep low – no operation started

  // Data bus
  wire [127:0] auth_data_i   = 128'd0;   // constant input data
  wire [127:0] auth_data_o;             // will be left unconnected
  wire        auth_valid_o;             // will be left unconnected

  // EEPROM interface (must be passed through unchanged)
  wire        auth_eeprom_busy   = eeprom_busy;
  wire        auth_eeprom_done   = eeprom_done;
  wire [127:0] auth_eeprom_buffer = eeprom_rbuffer;
  wire        auth_eeprom_start;       // driven by auth
  wire        auth_eeprom_get_key;     // driven by auth

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
      .mfrc_trx_valid(mfrc_trx_valid),
      .mfrc_trx_ready(mfrc_trx_ready),
      .mfrc_trx_tx_len(mfrc_trx_tx_len),
      .mfrc_trx_tx_data(mfrc_trx_tx_data),
      .mfrc_trx_tx_last_bits(mfrc_trx_tx_last_bits),
      .mfrc_trx_timeout_cycles(mfrc_trx_timeout_cycles),
      .mfrc_trx_done(mfrc_trx_done),
      .mfrc_trx_ok(mfrc_trx_ok),
      .mfrc_trx_rx_len(mfrc_trx_rx_len),
      .mfrc_trx_rx_data(mfrc_trx_rx_data),
      .mfrc_trx_rx_last_bits(mfrc_trx_rx_last_bits),
      .mfrc_trx_error(mfrc_trx_error),

      // SPI bus
      .spi_sclk(spi_sclk),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .cs_0(cs_0),
      .cs_1(cs_1)
  );

  auth u_auth(
       .clk               (clk),
      .rst               (rst),

      // Control
      .operation_i       (auth_operation_i),
      .start_i           (auth_start_i),

      // Data bus
      .data_i            (auth_data_i),
      .data_o            (auth_data_o),   // left unconnected downstream
      .valid_o           (auth_valid_o),  // left unconnected downstream

      // EEPROM interface (passed through)
      .eeprom_busy       (auth_eeprom_busy),
      .eeprom_done       (auth_eeprom_done),
      .eeprom_buffer     (auth_eeprom_buffer),
      .eeprom_start      (auth_eeprom_start),
      .eeprom_get_key    (auth_eeprom_get_key)
    );

  assign status_busy = eeprom_busy;

endmodule

