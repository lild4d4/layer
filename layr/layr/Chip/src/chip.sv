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
    (* MARK_DEBUG = "TRUE" *) output wire status_fault,
    (* MARK_DEBUG = "TRUE" *) output wire status_unlock,
    (* MARK_DEBUG = "TRUE" *) output wire status_busy
);

  (* MARK_DEBUG = "TRUE" *) wire layr_status;
  (* MARK_DEBUG = "TRUE" *) wire layr_status_valid;

  // EEPROM interface signals
  (* MARK_DEBUG = "TRUE" *) wire         eeprom_busy;
  (* MARK_DEBUG = "TRUE" *) wire         eeprom_done;
  wire [127:0] eeprom_rbuffer;

  // Tie off MFRC interface signals
  (* MARK_DEBUG = "TRUE" *) wire         mfrc_tx_valid;
  (* MARK_DEBUG = "TRUE" *) wire         mfrc_tx_ready;
  (* MARK_DEBUG = "TRUE" *) wire [  4:0] mfrc_tx_len;
  wire [255:0] mfrc_tx_data;
  wire [  2:0] mfrc_tx_last_bits;
  (* MARK_DEBUG = "TRUE" *) wire [  1:0] mfrc_tx_kind;

  (* MARK_DEBUG = "TRUE" *) wire         mfrc_rx_valid;
  (* MARK_DEBUG = "TRUE" *) wire [  4:0] mfrc_rx_len;
  wire [255:0] mfrc_rx_data;
  wire [  2:0] mfrc_rx_last_bits;

  (* MARK_DEBUG = "TRUE" *) wire         mfrc_card_present;

  // EEPROM interface (must be passed through unchanged)
  wire        auth_eeprom_busy   = eeprom_busy;
  wire        auth_eeprom_done   = eeprom_done;
  wire [127:0] auth_eeprom_buffer = eeprom_rbuffer;
  (* MARK_DEBUG = "TRUE" *) wire        auth_eeprom_start;       // driven by auth
  (* MARK_DEBUG = "TRUE" *) wire        auth_eeprom_get_key;     // driven by auth

  (* MARK_DEBUG = "TRUE" *) wire        mfrc_ready,mfrc_init_done;
  wire [15:0] mfrc_atqa;

  // results
  (* MARK_DEBUG = "TRUE" *) reg        unlocked;
  (* MARK_DEBUG = "TRUE" *) reg        forbidden;

  spi_top u_spi (
      .clk(clk),
      .rst(rst),

      .mfrc_ready(mfrc_ready),
      .mfrc_init_done(mfrc_init_done),
      .mfrc_card_present(mfrc_card_present),
      .mfrc_atqa(mfrc_atqa),


      // eeprom interface
      .eeprom_start(auth_eeprom_start),
      .eeprom_busy(eeprom_busy),
      .eeprom_done(eeprom_done),
      .eeprom_get_key(auth_eeprom_get_key),
      .eeprom_rbuffer(eeprom_rbuffer),

      // mfrc interface (tied off)
      .mfrc_tx_valid(mfrc_tx_valid),
      .mfrc_tx_ready(mfrc_tx_ready),
      .mfrc_tx_len(mfrc_tx_len),
      .mfrc_tx_data(mfrc_tx_data),
      .mfrc_tx_last_bits(mfrc_tx_last_bits),
      .mfrc_tx_kind(mfrc_tx_kind),

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
      .soft_rst          (layr_rst),
      .busy              (status_busy),

      .card_present_i(mfrc_card_present),

      .mfrc_tx_valid(mfrc_tx_valid),
      .mfrc_tx_ready(mfrc_tx_ready),
      .mfrc_tx_len(mfrc_tx_len),
      .mfrc_tx_data(mfrc_tx_data),
      .mfrc_tx_last_bits(mfrc_tx_last_bits),
      .mfrc_tx_kind(mfrc_tx_kind),

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

  localparam DISPLAY_CYCLES = 500_000_000; // 5 s @ 100 MHz
  reg [29:0] display_cnt;
  reg        layr_rst;

  assign status_unlock = unlocked;
  assign status_fault  = forbidden;

  always_ff @(posedge clk) begin
    if (rst) begin
      unlocked    <= 0;
      forbidden   <= 0;
      display_cnt <= 0;
      layr_rst    <= 0;
    end else begin
      layr_rst <= 0; // default: de-assert every cycle
      if (layr_status_valid) begin
        // latch result and (re)start the 5-second display timer
        unlocked    <= layr_status;
        forbidden   <= ~layr_status;
        display_cnt <= 0;
      end else if (unlocked || forbidden) begin
        if (display_cnt == DISPLAY_CYCLES - 1) begin
          unlocked    <= 0;
          forbidden   <= 0;
          display_cnt <= 0;
          layr_rst    <= 1;
        end else begin
          display_cnt <= display_cnt + 1;
        end
      end
    end
  end
  

endmodule
