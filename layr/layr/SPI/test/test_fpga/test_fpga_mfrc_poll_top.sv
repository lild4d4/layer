module test_fpga_mfrc_poll_top (
    input         clk,
    (* MARK_DEBUG = "TRUE" *) input         rst,

    (* MARK_DEBUG = "TRUE" *) output logic [3:0] led,

    // SPI bus
    (* MARK_DEBUG = "TRUE" *) output wire       sclk,
    (* MARK_DEBUG = "TRUE" *) output wire       mosi,
    (* MARK_DEBUG = "TRUE" *) input  wire       miso,
    (* MARK_DEBUG = "TRUE" *) output wire       cs1,
    (* MARK_DEBUG = "TRUE" *) output wire       cs0
);

  // eeprom  
  logic        eeprom_start;
  wire         eeprom_done;
  wire         eeprom_busy;
  logic        eeprom_get_key;
  wire [127:0] eeprom_buffer;

  // mfrc status outputs
  wire        mfrc_ready;         // 1 = idle/ready
  (* MARK_DEBUG = "TRUE" *) wire        mfrc_init_done;     // 1 = init complete
  (* MARK_DEBUG = "TRUE" *) wire        mfrc_card_present;  // 1 = card detected
  (* MARK_DEBUG = "TRUE" *) wire [15:0] mfrc_atqa;          // ATQA response

  // mfrc TX interface (to card)
  (* MARK_DEBUG = "TRUE" *) wire         mfrc_tx_valid;
  (* MARK_DEBUG = "TRUE" *) wire         mfrc_tx_ready;
  (* MARK_DEBUG = "TRUE" *) wire [  4:0] mfrc_tx_len;
  wire [255:0] mfrc_tx_data;
  (* MARK_DEBUG = "TRUE" *) wire [  2:0] mfrc_tx_last_bits;
  wire [  1:0] mfrc_tx_kind;

  // mfrc RX interface (from card)
  (* MARK_DEBUG = "TRUE" *) wire         mfrc_rx_valid;
  (* MARK_DEBUG = "TRUE" *) wire [  4:0] mfrc_rx_len;
  wire [255:0] mfrc_rx_data;
  (* MARK_DEBUG = "TRUE" *) wire [  2:0] mfrc_rx_last_bits;


  spi_top spi_dut (
    .clk(clk),
    .rst(rst),

    // eeprom interface
    .eeprom_start(eeprom_start),
    .eeprom_busy(eeprom_busy),
    .eeprom_done(eeprom_done),
    .eeprom_get_key(eeprom_get_key),  // get_key = 1, get_id = 0
    .eeprom_rbuffer(eeprom_buffer),

    // mfrc status outputs
    .mfrc_ready(mfrc_ready),         // 1 = idle/ready
    .mfrc_init_done(mfrc_init_done),     // 1 = init complete
    .mfrc_card_present(mfrc_card_present),  // 1 = card detected
    .mfrc_atqa(mfrc_atqa),          // ATQA response
  
    // mfrc TX interface (to card)
    .mfrc_tx_valid(mfrc_tx_valid),
    .mfrc_tx_ready(mfrc_tx_ready),
    .mfrc_tx_len(mfrc_tx_len),
    .mfrc_tx_data(mfrc_tx_data),
    .mfrc_tx_last_bits(mfrc_tx_last_bits),
    .mfrc_tx_kind(mfrc_tx_kind),
  
    // mfrc RX interface (from card)
    .mfrc_rx_valid(mfrc_rx_valid),
    .mfrc_rx_len(mfrc_rx_len),
    .mfrc_rx_data(mfrc_rx_data),
    .mfrc_rx_last_bits(mfrc_rx_last_bits),

    // spi bus output
    .spi_sclk(sclk),
    .spi_mosi(mosi),
    .spi_miso(miso),
    .cs_0(cs0),  // active-low chip select – MFRC522
    .cs_1(cs1)  // active-low chip select – AT25010B
);

  localparam [32:0]   DELAY_CYCLES = 32'd200_000_000;

  reg [32:0] ctr;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      ctr     <= DELAY_CYCLES;
      led <= 4'b0000;
    end else begin
      led[1] <= mfrc_card_present;
      if (ctr == 0) begin
        ctr <= DELAY_CYCLES;
      end else begin
        ctr <= ctr - 1;
      end

      if (ctr == DELAY_CYCLES / 2 )
        led[0] <= 1;
    end
  end
endmodule
