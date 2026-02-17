// mfrc_top – MFRC522 top-level wrapper
//
// Provides:
//   - Initialization sequence (soft reset + register writes)
//   - Automatic card polling until card is detected
//   - Simple TX/RX interface for communication with card
//
// Usage:
//   - Pulses cmd_init to run initialization (auto-runs on power-up)
//   - Pulses cmd_poll for manual poll
//   - Read card_present to detect card
//   - Use tx_* / rx_* for sending/receiving data

module mfrc_top (
    input wire clk,
    input wire rst,

    // ── command inputs ──
    input wire cmd_init,  // pulse to re-run initialization
    input wire cmd_poll,  // pulse for manual poll

    // ── status outputs ──
    output wire        ready,         // 1 = idle/ready for commands
    output wire        init_done,     // 1 = initialization complete
    output wire        card_present,  // 1 = card detected
    output wire [15:0] atqa,          // ATQA response (2 bytes)
    output wire [ 7:0] status,        // 0=OK, non-zero=error

    // ── TX interface (to card) ──
    input  wire         tx_valid,
    output wire         tx_ready,
    input  wire [  4:0] tx_len,        // 0..31 → 1..32 bytes
    input  wire [255:0] tx_data,       // byte0 at [255:248]
    input  wire [  2:0] tx_last_bits,  // 0 for full bytes, 7 for REQA/WUPA
    input  wire [ 31:0] tx_timeout,    // timeout in SPI cycles

    // ── RX interface (from card) ──
    output wire         rx_valid,      // pulse when rx_data is valid
    output wire         rx_ok,         // 1 = successful transfer
    output wire [  4:0] rx_len,        // bytes received
    output wire [255:0] rx_data,       // byte0 at [255:248]
    output wire [  2:0] rx_last_bits,
    output wire [  7:0] rx_error,

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
  localparam logic [31:0] RESET_CYCLES = 32'd5_000;


  // =====================================================================
  // MFRC522 register addresses (6-bit, as used by mfrc_reg_if)
  // =====================================================================
  localparam logic [5:0] REG_COMMAND = 6'h01;
  localparam logic [5:0] REG_TX_MODE = 6'h12;
  localparam logic [5:0] REG_RX_MODE = 6'h13;
  localparam logic [5:0] REG_MOD_WIDTH = 6'h24;
  localparam logic [5:0] REG_T_MODE = 6'h2A;
  localparam logic [5:0] REG_T_PRESCALER = 6'h2B;
  localparam logic [5:0] REG_T_RELOAD_H = 6'h2C;
  localparam logic [5:0] REG_T_RELOAD_L = 6'h2D;
  localparam logic [5:0] REG_TX_ASK = 6'h15;
  localparam logic [5:0] REG_MODE = 6'h11;
  localparam logic [5:0] REG_TX_CONTROL = 6'h14;

  // =====================================================================
  // MFRC522 commands
  // =====================================================================
  localparam logic [7:0] CMD_SOFT_RESET = 8'h0F;
  localparam logic [7:0] PICC_REQA = 8'h26;  // 7-bit command

  // =====================================================================
  // State machine states
  // =====================================================================
  localparam logic [3:0] S_IDLE = 4'd0;
  localparam logic [3:0] S_SOFT_RESET = 4'd1;
  localparam logic [3:0] S_WAIT_RESET = 4'd2;
  localparam logic [3:0] S_INIT_WRITE = 4'd3;
  localparam logic [3:0] S_INIT_WAIT = 4'd4;
  localparam logic [3:0] S_ANTENNA_ON = 4'd5;
  localparam logic [3:0] S_POLL_SETUP = 4'd6;
  localparam logic [3:0] S_POLL_WAIT = 4'd7;
  localparam logic [3:0] S_POLL_RESULT = 4'd8;

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
  wire [ 31:0] trx_timeout_cycles;

  wire         trx_done;
  wire         trx_ok;
  wire [  4:0] trx_rx_len;
  wire [255:0] trx_rx_data;
  wire [  2:0] trx_rx_last_bits;
  wire [  7:0] trx_error;

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
  reg          card_present_r;
  reg  [ 15:0] atqa_r;
  reg  [  7:0] status_r;
  reg          ready_r;
  reg          rx_valid_r;

  // =====================================================================
  // Instantiate reg_arb (shares reg_if between FSM and mfrc_core)
  // =====================================================================
  reg          init_done_sync;

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
      .m_resp_ok(reg_resp_ok),

      .init_done(init_done_sync)
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
      .trx_timeout_cycles(trx_timeout_cycles),

      .trx_done(trx_done),
      .trx_ok(trx_ok),
      .trx_rx_len(trx_rx_len),
      .trx_rx_data(trx_rx_data),
      .trx_rx_last_bits(trx_rx_last_bits),
      .trx_error(trx_error),

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
      .spi_rx_data(256'd0)  // Not used - we use reg interface only
  );

  // =====================================================================
  // Main FSM (init + polling)
  // =====================================================================
  reg [3:0] state;
  reg cmd_init_d1, cmd_poll_d1;
  wire         cmd_init_pulse = cmd_init && !cmd_init_d1;
  wire         cmd_poll_pulse = cmd_poll && !cmd_poll_d1;

  reg  [  3:0] init_idx;
  reg  [ 31:0] wait_cnt;

  reg          trx_v;
  reg  [  4:0] trx_len_r;
  reg  [255:0] trx_data_r;
  reg  [  2:0] trx_last_r;
  reg  [ 31:0] trx_timeout_r;

  assign trx_valid = trx_v;
  assign trx_tx_len = trx_len_r;
  assign trx_tx_data = trx_data_r;
  assign trx_tx_last_bits = trx_last_r;
  assign trx_timeout_cycles = trx_timeout_r;

  // Sync init_done to arbiter (avoid combinational loop)
  always @(posedge clk) begin
    init_done_sync <= init_done_r;
  end

  assign ready        = ready_r;
  assign init_done    = init_done_r;
  assign card_present = card_present_r;
  assign atqa         = atqa_r;
  assign status       = status_r;

  assign rx_valid     = rx_valid_r;
  assign rx_ok        = trx_ok;
  assign rx_len       = trx_rx_len;
  assign rx_data      = trx_rx_data;
  assign rx_last_bits = trx_rx_last_bits;
  assign rx_error     = trx_error;

  assign tx_ready     = trx_ready;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state          <= S_IDLE;
      cmd_init_d1    <= 1'b0;
      cmd_poll_d1    <= 1'b0;
      ready_r        <= 1'b1;
      init_done_r    <= 1'b0;
      card_present_r <= 1'b0;
      atqa_r         <= 16'd0;
      status_r       <= 8'd0;
      init_idx       <= 4'd0;
      wait_cnt       <= 32'd0;
      trx_v          <= 1'b0;
      fsm_req_valid  <= 1'b0;
      rx_valid_r     <= 1'b0;
    end else begin
      cmd_init_d1   <= cmd_init;
      cmd_poll_d1   <= cmd_poll;

      trx_v         <= 1'b0;
      fsm_req_valid <= 1'b0;
      rx_valid_r    <= 1'b0;

      case (state)
        S_IDLE: begin
          ready_r        <= 1'b1;
          card_present_r <= 1'b0;
          atqa_r         <= 16'd0;

          if (cmd_init_pulse || !init_done_r) begin
            state       <= S_SOFT_RESET;
            ready_r     <= 1'b0;
            status_r    <= 8'd0;
            init_idx    <= 4'd0;
            init_done_r <= 1'b0;
          end else if (cmd_poll_pulse && init_done_r) begin
            state         <= S_POLL_SETUP;
            ready_r       <= 1'b0;
            trx_len_r     <= 5'd1;
            trx_data_r    <= {PICC_REQA, 248'd0};
            trx_last_r    <= 3'd7;
            trx_timeout_r <= 32'd2000;
          end else if (init_done_r && !card_present_r) begin
            state         <= S_POLL_SETUP;
            ready_r       <= 1'b0;
            trx_len_r     <= 5'd1;
            trx_data_r    <= {PICC_REQA, 248'd0};
            trx_last_r    <= 3'd7;
            trx_timeout_r <= 32'd2000;
          end
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
          if (trx_ready) begin
            trx_v <= 1'b1;
            state <= S_POLL_WAIT;
          end
        end

        S_POLL_WAIT: begin
          if (trx_done) begin
            state <= S_POLL_RESULT;
          end
        end

        S_POLL_RESULT: begin
          if (trx_ok && trx_rx_len == 5'd2) begin
            card_present_r <= 1'b1;
            atqa_r[7:0] <= trx_rx_data[255:248];
            atqa_r[15:8] <= trx_rx_data[247:240];
          end else begin
            card_present_r <= 1'b0;
            atqa_r         <= 16'd0;
          end
          status_r <= trx_error;
          state    <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
