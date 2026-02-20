module test_2e2_fpga_top (
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

  // mfrc status
  wire         mfrc_ready;
  wire         mfrc_init_done;
  wire         mfrc_card_present;
  wire [15:0] mfrc_atqa;

  // mfrc TX interface
  logic        mfrc_tx_valid;
  wire         mfrc_tx_ready;
  logic [  4:0] mfrc_tx_len;
  logic [255:0] mfrc_tx_data;
  logic [  2:0] mfrc_tx_last_bits;
  logic [  1:0] mfrc_tx_kind;

  // mfrc RX interface
  wire         mfrc_rx_valid;
  wire [  4:0] mfrc_rx_len;
  wire [255:0] mfrc_rx_data;
  wire [  2:0] mfrc_rx_last_bits;

  spi_top spi_dut (
    .clk(clk),
    .rst(rst),

    // eeprom interface
    .eeprom_start(eeprom_start),
    .eeprom_busy(eeprom_busy),
    .eeprom_done(eeprom_done),
    .eeprom_get_key(eeprom_get_key),  // get_key = 1, get_id = 0
    .eeprom_rbuffer(eeprom_buffer),

    // mfrc interface
    .mfrc_ready(mfrc_ready),
    .mfrc_init_done(mfrc_init_done),
    .mfrc_card_present(mfrc_card_present),
    .mfrc_atqa(mfrc_atqa),
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

    // spi bus output
    .spi_sclk(sclk),
    .spi_mosi(mosi),
    .spi_miso(miso),
    .cs_0(cs0),  // active-low chip select – MFRC522
    .cs_1(cs1)  // active-low chip select – AT25010B
);

  localparam [23:0]   DELAY_CYCLES = 24'd200_000;
  localparam [127:0]  KEY_A = 128'h39558d1f193656ab8b4b65e25ac48474;
  localparam [127:0]  ID_A  = 128'hbbe8278a67f960605adafd6f63cf7ba7;

  typedef enum logic [2:0] {
    S_IDLE,
    S_START,
    S_WAIT,
    S_DELAY
  } state_t;

  (* MARK_DEBUG = "TRUE" *) state_t state;
  reg [23:0] ctr;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state   <= S_IDLE;
      ctr     <= DELAY_CYCLES;
      led     <= 4'b0000;

      // eeprom  
      eeprom_start <= 0;
      eeprom_get_key <= 0;

      // mfrc
      mfrc_tx_valid <= 0;
      mfrc_tx_len <= 0;
      mfrc_tx_data <= 0;
      mfrc_tx_last_bits <= 0;
      mfrc_tx_kind <= 0;

    end else begin
      eeprom_start <= 1'b0;          // default: pulse only one cycle

      case (state)
        // wait after reset before first trigger
        S_IDLE: begin
          if (ctr == 0) begin
            eeprom_get_key <= ~eeprom_get_key;
            state <= S_START;
          end else begin
            ctr <= ctr - 1;
          end
        end

        // pulse start for one cycle
        S_START: begin
          eeprom_start <= 1'b1;
          state <= S_WAIT;
        end

        // wait for done
        S_WAIT: begin
          if (eeprom_done) begin
            led[0] <= ~led[0];           // toggle heartbeat
            if (eeprom_get_key == 0) begin // get id
              if (eeprom_buffer[127:0] == ID_A)
                led[1] <= 1'b1;  // ID VALID
              else
                led[1] <= 1'b0;
            end else begin // get key
              if (eeprom_buffer[127:0] == KEY_A)
                led[2] <= 1'b1; // KEY VALID
              else
                led[2] <= 1'b0;
            end
            ctr   <= DELAY_CYCLES;
            state <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
