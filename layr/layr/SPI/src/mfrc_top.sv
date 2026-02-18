// mfrc_top – MFRC522 top-level wrapper
//
// Provides:
//   - Initialization sequence (soft reset + register writes, auto-runs on power-up)
//   - Automatic card polling until card is detected
//   - Simple TX/RX interface for communication with card
//
// Usage:
//   - Read card_present for one-cycle pulse when card detected
//   - Use tx_* / rx_* for sending/receiving data
//
// Note: Once a card is detected, polling stops. Reset the module to resume polling.

module mfrc_top (
    input wire clk,
    input wire rst,

    // ── status outputs ──
    output wire        ready,         // 1 = idle/ready for commands
    output wire        init_done,     // 1 = initialization complete
    output wire        card_present,  // 1-cycle pulse when card detected
    output wire [15:0] atqa,          // ATQA response (2 bytes)

    // ── TX interface (to card) ──
    input  wire         tx_valid,
    output wire         tx_ready,
    input  wire [  4:0] tx_len,       // 0..31 → 1..32 bytes
    input  wire [255:0] tx_data,      // byte0 at [255:248]
    input  wire [  2:0] tx_last_bits, // 0 for full bytes, 7 for REQA/WUPA

    // ── RX interface (from card) ──
    output wire         rx_valid,     // pulse when rx_data is valid
    output wire [  4:0] rx_len,       // bytes received
    output wire [255:0] rx_data,      // byte0 at [255:248]
    output wire [  2:0] rx_last_bits,

    // ── SPI signals (to spi_arb) ──
    input  wire         spi_done,
    input  wire         spi_busy,
    input  wire [255:0] spi_rx_data,
    output wire [255:0] spi_tx_data,
    output wire [  5:0] spi_w_len,
    output wire [  5:0] spi_r_len,
    output wire         spi_go
);
  // RESET CYCLES
  // TODO: INCREASE THIS TO 50ms ON REAL HARDWARE!
  localparam logic [31:0] RESET_CYCLES = 32'd5_000_000;
  // 5mil.


  // =====================================================================
  // MFRC522 register addresses (6-bit, as used by mfrc_reg_if)
  // =====================================================================
  typedef enum logic [5:0] {
    REG_COMMAND     = 6'h01,
    REG_MODE        = 6'h11,
    REG_TX_MODE     = 6'h12,
    REG_RX_MODE     = 6'h13,
    REG_TX_CONTROL  = 6'h14,
    REG_TX_ASK      = 6'h15,
    REG_MOD_WIDTH   = 6'h24,
    REG_T_MODE      = 6'h2A,
    REG_T_PRESCALER = 6'h2B,
    REG_T_RELOAD_H  = 6'h2C,
    REG_T_RELOAD_L  = 6'h2D
  } mfrc522_reg_t;

  // =====================================================================
  // MFRC522 commands
  // =====================================================================
  typedef enum logic [7:0] {
    CMD_SOFT_RESET = 8'h0F,
    PICC_REQA      = 8'h26   // 7-bit command
  } mfrc522_cmd_t;

  // =====================================================================
  // State machine states
  // =====================================================================
  typedef enum logic [3:0] {
    S_IDLE        = 4'd0,
    S_SOFT_RESET  = 4'd1,
    S_WAIT_RESET  = 4'd2,
    S_INIT_WRITE  = 4'd3,
    S_INIT_WAIT   = 4'd4,
    S_ANTENNA_ON  = 4'd5,
    S_POLL_SETUP  = 4'd6,
    S_POLL_WAIT   = 4'd7,
    S_POLL_RESULT = 4'd8
  } state_t;

  // =====================================================================
  // Init sequence data
  // =====================================================================
  localparam INIT_COUNT = 9;
  reg [5:0] init_addrs[0:INIT_COUNT-1];
  reg [7:0] init_vals [0:INIT_COUNT-1];

  initial begin
    init_addrs[0] = REG_TX_MODE;
    init_vals[0]  = 8'h00;
    init_addrs[1] = REG_RX_MODE;
    init_vals[1]  = 8'h00;
    init_addrs[2] = REG_MOD_WIDTH;
    init_vals[2]  = 8'h26;
    init_addrs[3] = REG_T_MODE;
    init_vals[3]  = 8'h80;
    init_addrs[4] = REG_T_PRESCALER;
    init_vals[4]  = 8'hA9;
    init_addrs[5] = REG_T_RELOAD_H;
    init_vals[5]  = 8'h03;
    init_addrs[6] = REG_T_RELOAD_L;
    init_vals[6]  = 8'hE8;
    init_addrs[7] = REG_TX_ASK;
    init_vals[7]  = 8'h40;
    init_addrs[8] = REG_MODE;
    init_vals[8]  = 8'h3D;
  end

  // =====================================================================
  // Internal wires for mfrc_core (trx interface)
  // =====================================================================
  wire         trx_valid;
  wire         trx_ready;
  wire [  4:0] trx_tx_len;
  wire [255:0] trx_tx_data;
  wire [  2:0] trx_tx_last_bits;

  wire         trx_done;
  wire [  4:0] trx_rx_len;
  wire [255:0] trx_rx_data;
  wire [  2:0] trx_rx_last_bits;

  // FSM register request signals (client A to arbiter)
  reg          fsm_req_valid;
  wire         fsm_req_ready;
  reg          fsm_req_write;
  reg  [  5:0] fsm_req_addr;
  reg  [  4:0] fsm_req_len;
  reg  [255:0] fsm_req_wdata;

  wire         fsm_resp_valid;
  wire [255:0] fsm_resp_rdata;
  wire         fsm_resp_ok;

  // Register interface to reg_if (from arbiter)
  wire         reg_req_valid;
  wire         reg_req_ready;
  wire         reg_req_write;
  wire [  5:0] reg_req_addr;
  wire [  4:0] reg_req_len;
  wire [255:0] reg_req_wdata;

  wire         reg_resp_valid;
  wire [255:0] reg_resp_rdata;
  wire         reg_resp_ok;

  // Internal state
  reg          init_done_r;
  reg          card_present_r;  // One-cycle pulse output
  reg          card_found_r;  // Latched: stops polling once set
  reg  [ 15:0] atqa_r;
  reg          ready_r;
  reg          rx_valid_r;

  // =====================================================================
  // Instantiate reg_arb (shares reg_if between FSM and mfrc_core)
  // =====================================================================
  // Intermediate wires for mfrc_core register interface
  wire         core_req_valid;
  wire         core_req_ready;
  wire         core_req_write;
  wire [  5:0] core_req_addr;
  wire [  4:0] core_req_len;
  wire [255:0] core_req_wdata;

  wire         core_resp_valid;
  wire [255:0] core_resp_rdata;
  wire         core_resp_ok;

  mfrc_reg_arb u_reg_arb (
      .clk(clk),
      .rst(rst),

      // FSM (Client A - initialization)
      .a_req_valid(fsm_req_valid),
      .a_req_ready(fsm_req_ready),
      .a_req_write(fsm_req_write),
      .a_req_addr(fsm_req_addr),
      .a_req_len(fsm_req_len),
      .a_req_wdata(fsm_req_wdata),
      .a_resp_valid(fsm_resp_valid),
      .a_resp_rdata(fsm_resp_rdata),
      .a_resp_ok(fsm_resp_ok),

      // mfrc_core (Client B - transceive)
      .b_req_valid(core_req_valid),
      .b_req_ready(core_req_ready),
      .b_req_write(core_req_write),
      .b_req_addr(core_req_addr),
      .b_req_len(core_req_len),
      .b_req_wdata(core_req_wdata),
      .b_resp_valid(core_resp_valid),
      .b_resp_rdata(core_resp_rdata),
      .b_resp_ok(core_resp_ok),

      // To mfrc_reg_if
      .m_req_valid(reg_req_valid),
      .m_req_ready(reg_req_ready),
      .m_req_write(reg_req_write),
      .m_req_addr(reg_req_addr),
      .m_req_len(reg_req_len),
      .m_req_wdata(reg_req_wdata),
      .m_resp_valid(reg_resp_valid),
      .m_resp_rdata(reg_resp_rdata),
      .m_resp_ok(reg_resp_ok)
  );

  // =====================================================================
  // Instantiate mfrc_core (handles transceive)
  // =====================================================================
  mfrc_core u_mfrc_core (
      .clk(clk),
      .rst(rst),

      .trx_valid(trx_valid),
      .trx_ready(trx_ready),
      .trx_tx_len(trx_tx_len),
      .trx_tx_data(trx_tx_data),
      .trx_tx_last_bits(trx_tx_last_bits),

      .trx_done(trx_done),
      .trx_rx_len(trx_rx_len),
      .trx_rx_data(trx_rx_data),
      .trx_rx_last_bits(trx_rx_last_bits),

      .reg_req_valid(core_req_valid),
      .reg_req_ready(core_req_ready),
      .reg_req_write(core_req_write),
      .reg_req_addr (core_req_addr),
      .reg_req_len  (core_req_len),
      .reg_req_wdata(core_req_wdata),

      .reg_resp_valid(core_resp_valid),
      .reg_resp_rdata(core_resp_rdata),
      .reg_resp_ok(core_resp_ok)
  );

  // =====================================================================
  // Instantiate mfrc_reg_if (handles SPI protocol)
  // =====================================================================
  mfrc_reg_if u_mfrc_reg_if (
      .clk(clk),
      .rst(rst),

      .req_valid(reg_req_valid),
      .req_ready(reg_req_ready),
      .req_write(reg_req_write),
      .req_addr (reg_req_addr),
      .req_len  (reg_req_len),
      .req_wdata(reg_req_wdata),

      .resp_valid(reg_resp_valid),
      .resp_rdata(reg_resp_rdata),
      .resp_ok(reg_resp_ok),

      .spi_go(spi_go),
      .spi_done(spi_done),
      .spi_busy(spi_busy),
      .spi_w_len(spi_w_len),
      .spi_r_len(spi_r_len),
      .spi_tx_data(spi_tx_data),
      .spi_rx_data(spi_rx_data)
  );

  // =====================================================================
  // Main FSM (init + polling)
  // =====================================================================
  (* MARK_DEBUG = "TRUE" *) state_t state;

  reg     [  3:0] init_idx;
  reg     [ 31:0] wait_cnt;

  reg             trx_v;
  reg     [  4:0] trx_len_r;
  reg     [255:0] trx_data_r;
  reg     [  2:0] trx_last_r;

  // Use external TX signals when tx_valid is asserted, otherwise use internal auto-poll
  assign trx_valid        = tx_valid || trx_v;
  assign trx_tx_len       = tx_valid ? tx_len : trx_len_r;
  assign trx_tx_data      = tx_valid ? tx_data : trx_data_r;
  assign trx_tx_last_bits = tx_valid ? tx_last_bits : trx_last_r;

  assign rx_valid         = (card_found_r && trx_done) ? 1'b1 : 1'b0;

  assign ready            = ready_r;
  assign init_done        = init_done_r;
  assign card_present     = card_present_r;
  assign atqa             = atqa_r;

  assign rx_len           = trx_rx_len;
  assign rx_data          = trx_rx_data;
  assign rx_last_bits     = trx_rx_last_bits;

  assign tx_ready         = trx_ready;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state          <= S_IDLE;
      ready_r        <= 1'b1;
      init_done_r    <= 1'b0;
      card_present_r <= 1'b0;
      card_found_r   <= 1'b0;
      atqa_r         <= 16'd0;
      init_idx       <= 4'd0;
      wait_cnt       <= 32'd0;
      trx_v          <= 1'b0;
      fsm_req_valid  <= 1'b0;
    end else begin
      trx_v          <= 1'b0;
      fsm_req_valid  <= 1'b0;
      card_present_r <= 1'b0;  // Default: pulse is low

      case (state)
        S_IDLE: begin
          ready_r <= 1'b1;

          if (!init_done_r) begin
            state       <= S_SOFT_RESET;
            ready_r     <= 1'b0;
            init_idx    <= 4'd0;
            init_done_r <= 1'b0;
          end else if (!card_found_r) begin
            // Only poll if we haven't found a card yet
            state      <= S_POLL_SETUP;
            ready_r    <= 1'b0;
            trx_len_r  <= 5'd0;
            trx_data_r <= {PICC_REQA, 248'd0};
            trx_last_r <= 3'd7;
          end
          // If card_found_r is set, stay in S_IDLE (no more polling)
        end

        S_SOFT_RESET: begin
          if (fsm_req_ready) begin
            fsm_req_valid <= 1'b1;
            fsm_req_write <= 1'b1;
            fsm_req_addr  <= REG_COMMAND;
            fsm_req_len   <= 5'd0;
            fsm_req_wdata <= {CMD_SOFT_RESET, 248'd0};
            state         <= S_WAIT_RESET;
          end
        end

        S_WAIT_RESET: begin
          if (fsm_resp_valid) begin
            wait_cnt <= RESET_CYCLES;
          end else if (wait_cnt > 32'd0) begin
            if (wait_cnt == 32'd1) begin
              state    <= S_INIT_WRITE;
              init_idx <= 4'd0;
            end

            wait_cnt <= wait_cnt - 32'd1;
          end
        end

        S_INIT_WRITE: begin
          if (fsm_req_ready) begin
            fsm_req_valid <= 1'b1;
            fsm_req_write <= 1'b1;
            fsm_req_addr  <= init_addrs[init_idx];
            fsm_req_len   <= 5'd0;
            fsm_req_wdata <= {init_vals[init_idx], 248'd0};
            state         <= S_INIT_WAIT;
          end
        end

        S_INIT_WAIT: begin
          if (fsm_resp_valid) begin
            if (init_idx < INIT_COUNT - 1) begin
              init_idx <= init_idx + 4'd1;
              state    <= S_INIT_WRITE;
            end else begin
              init_idx <= 4'd0;
              state    <= S_ANTENNA_ON;
            end
          end
        end

        S_ANTENNA_ON: begin
          if (fsm_req_ready) begin
            fsm_req_valid <= 1'b1;
            fsm_req_write <= 1'b1;
            fsm_req_addr  <= REG_TX_CONTROL;
            fsm_req_len   <= 5'd0;
            fsm_req_wdata <= {8'h03, 248'd0};
            state         <= S_IDLE;
            init_done_r   <= 1'b1;
          end
        end

        S_POLL_SETUP: begin
          //if (trx_ready) begin
          //  trx_v <= 1'b1;
          //  state <= S_POLL_WAIT;
          //end
          state <= S_POLL_SETUP;
        end

        S_POLL_WAIT: begin
          if (trx_done) begin
            state <= S_POLL_RESULT;
          end
        end

        S_POLL_RESULT: begin
          if (trx_rx_len == 5'd2) begin
            card_present_r <= 1'b1;  // One-cycle pulse
            card_found_r <= 1'b1;  // Latched: stops future polling
            atqa_r[15:8] <= trx_rx_data[255:248];  // First byte (0x04) → high byte
            atqa_r[7:0] <= trx_rx_data[247:240];  // Second byte (0x00) → low byte
          end
          // If no card found, card_found_r stays 0 and we'll poll again
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule










