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

  // EEPROM interface signals
  wire         eeprom_busy;
  wire         eeprom_done;
  wire [127:0] eeprom_rbuffer;

  // Tie off MFRC interface signals
  wire         mfrc_tx_valid;
  wire         mfrc_tx_ready;
  wire [  4:0] mfrc_tx_len;
  wire [255:0] mfrc_tx_data;
  wire [  2:0] mfrc_tx_last_bits;
  wire [  1:0] mfrc_tx_kind;

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

  wire        mfrc_ready,mfrc_init_done;
  wire [15:0] mfrc_atqa;

  // results
  reg        unlocked;
  reg        forbidden;

  localparam BUSY_TIMEOUT_CYCLES   = 50_000_000; // 0.5 s @ 100 MHz  (no result)
  localparam DISPLAY_CYCLES        = 500_000_000; // 5 s @ 100 MHz  (success/fault)
  reg [28:0] timer_cnt;
  reg        layr_rst;
  reg        timer_running;
  reg        got_result;      // 1 = success/fault latched, use 5 s; 0 = busy-only, use 1 s

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

  assign status_unlock = unlocked;
  assign status_fault  = forbidden;

  always_ff @(posedge clk) begin
    if (rst) begin
      unlocked      <= 0;
      forbidden     <= 0;
      timer_cnt     <= 0;
      layr_rst      <= 0;
      timer_running <= 0;
      got_result    <= 0;
    end else begin
      layr_rst <= 0; // default: de-assert every cycle

      if (layr_status_valid) begin
        // latch result and (re)start the 5-second display timer
        unlocked      <= layr_status;
        forbidden     <= ~layr_status;
        timer_cnt     <= 0;
        timer_running <= 1;
        got_result    <= 1;
      end else begin
        // only run the timer / start logic when status_valid is NOT active
        if (!timer_running && status_busy) begin
          // start 1-second timeout as soon as busy goes high
          timer_cnt     <= 0;
          timer_running <= 1;
          got_result    <= 0;
        end else if (timer_running) begin
          if (timer_cnt == (got_result ? DISPLAY_CYCLES - 1 : BUSY_TIMEOUT_CYCLES - 1)) begin
            unlocked      <= 0;
            forbidden     <= 0;
            timer_cnt     <= 0;
            layr_rst      <= 1;
            timer_running <= 0;
            got_result    <= 0;
          end else begin
            timer_cnt <= timer_cnt + 1;
          end
        end
      end
    end
  end
  

endmodule
