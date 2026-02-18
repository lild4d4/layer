// mfrc_core – simplified MFRC522 transceive controller
//
// Fully linear FSM: each state does one register operation then advances.
// No timeout counting or error analysis — higher layers handle that
// by pulling a hard reset and retrying if needed.
//
// Happy path only:
//   1. Flush FIFO
//   2. Write BitFramingReg (tx last bits)
//   3. Write TX data to FIFO
//   4. Write CommandReg = Transceive
//   5. Write BitFramingReg with StartSend
//   6. Poll ComIrqReg until RxIRq
//   7. Write CommandReg = Idle
//   8. Read FIFOLevelReg
//   9. Read FIFO data
//  10. Read ControlReg (rx last bits)
//  11. Done
//
// Length encoding follows mfrc_reg_if: 5-bit, 0 = 1 byte, 31 = 32 bytes.

module mfrc_core (
    input wire clk,
    input wire rst,

    // ── Transceive request ──
    input  wire         trx_valid,
    output wire         trx_ready,
    input  wire [  4:0] trx_tx_len,
    input  wire [255:0] trx_tx_data,
    input  wire [  2:0] trx_tx_last_bits,

    // ── Transceive response ──
    output reg         trx_done,
    output reg [  4:0] trx_rx_len,
    output reg [255:0] trx_rx_data,
    output reg [  2:0] trx_rx_last_bits,

    // ── mfrc_reg_if request/response interface ──
    output reg          reg_req_valid,
    input  wire         reg_req_ready,
    output reg          reg_req_write,
    output reg  [  5:0] reg_req_addr,
    output reg  [  4:0] reg_req_len,
    output reg  [255:0] reg_req_wdata,

    input wire         reg_resp_valid,
    input wire [255:0] reg_resp_rdata,
    input wire         reg_resp_ok
);

  // ── Register addresses ──
  typedef enum logic [5:0] {
    REG_COMMAND     = 6'h01,
    REG_COM_IRQ     = 6'h04,
    REG_FIFO_DATA   = 6'h09,
    REG_FIFO_LEVEL  = 6'h0A,
    REG_CONTROL     = 6'h0C,
    REG_BIT_FRAMING = 6'h0D
  } mfrc522_reg_t;

  // ── Constants ──
  typedef enum logic [7:0] {
    CMD_IDLE       = 8'h00,
    CMD_TRANSCEIVE = 8'h0C,
    IRQ_RX         = 8'h20,
    FIFO_FLUSH     = 8'h80
  } mfrc522_const_t;

  // ── FSM states (fully linear) ──
  typedef enum logic [4:0] {
    S_IDLE           = 5'd0,
    S_FLUSH_ISSUE    = 5'd1,
    S_FLUSH_WAIT     = 5'd2,
    S_BITFR_ISSUE    = 5'd3,
    S_BITFR_WAIT     = 5'd4,
    S_FIFOWR_ISSUE   = 5'd5,
    S_FIFOWR_WAIT    = 5'd6,
    S_CMD_ISSUE      = 5'd7,
    S_CMD_WAIT       = 5'd8,
    S_START_ISSUE    = 5'd9,
    S_START_WAIT     = 5'd10,
    S_POLL_ISSUE     = 5'd11,
    S_POLL_WAIT      = 5'd12,
    S_IDLE_CMD_ISSUE = 5'd13,
    S_IDLE_CMD_WAIT  = 5'd14,
    S_RDLVL_ISSUE    = 5'd15,
    S_RDLVL_WAIT     = 5'd16,
    S_RDFIFO_ISSUE   = 5'd17,
    S_RDFIFO_WAIT    = 5'd18,
    S_RDCTRL_ISSUE   = 5'd19,
    S_RDCTRL_WAIT    = 5'd20,
    S_DONE           = 5'd21
  } state_t;

  state_t state;

  // Latched request
  reg [4:0] lat_tx_len;
  reg [255:0] lat_tx_data;
  reg [2:0] lat_tx_last_bits;
  reg [5:0] fifo_level;

  assign trx_ready = (state == S_IDLE);

  // ── Helper: issue a register operation ──
  // Each _ISSUE state loads the bus signals and waits for ready.
  // Each _WAIT state waits for resp_valid then moves on.

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state            <= S_IDLE;
      reg_req_valid    <= 1'b0;
      reg_req_write    <= 1'b0;
      reg_req_addr     <= 6'd0;
      reg_req_len      <= 5'd0;
      reg_req_wdata    <= 256'd0;
      trx_done         <= 1'b0;
      trx_rx_len       <= 5'd0;
      trx_rx_data      <= 256'd0;
      trx_rx_last_bits <= 3'd0;
      fifo_level       <= 6'd0;
      lat_tx_len       <= 5'd0;
      lat_tx_data      <= 256'd0;
      lat_tx_last_bits <= 3'd0;
    end else begin
      reg_req_valid <= 1'b0;
      trx_done      <= 1'b0;

      case (state)

        // ── IDLE: latch request ──
        S_IDLE: begin
          if (trx_valid) begin
            lat_tx_len       <= trx_tx_len;
            lat_tx_data      <= trx_tx_data;
            lat_tx_last_bits <= trx_tx_last_bits;
            fifo_level       <= 6'd0;
            state            <= S_FLUSH_ISSUE;
          end
        end

        // ── 1. Flush FIFO ──
        S_FLUSH_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b1;
            reg_req_addr  <= REG_FIFO_LEVEL;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= {FIFO_FLUSH, 248'd0};
            state         <= S_FLUSH_WAIT;
          end
        end
        S_FLUSH_WAIT: if (reg_resp_valid) state <= S_BITFR_ISSUE;

        // ── 2. BitFramingReg (tx last bits, StartSend=0) ──
        S_BITFR_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b1;
            reg_req_addr  <= REG_BIT_FRAMING;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= {{5'b0, lat_tx_last_bits}, 248'd0};
            state         <= S_BITFR_WAIT;
          end
        end
        S_BITFR_WAIT: if (reg_resp_valid) state <= S_FIFOWR_ISSUE;

        // ── 3. Write TX data to FIFO ──
        S_FIFOWR_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b1;
            reg_req_addr  <= REG_FIFO_DATA;
            reg_req_len   <= lat_tx_len;
            reg_req_wdata <= lat_tx_data;
            state         <= S_FIFOWR_WAIT;
          end
        end
        S_FIFOWR_WAIT: if (reg_resp_valid) state <= S_CMD_ISSUE;

        // ── 4. CommandReg = Transceive ──
        S_CMD_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b1;
            reg_req_addr  <= REG_COMMAND;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= {CMD_TRANSCEIVE, 248'd0};
            state         <= S_CMD_WAIT;
          end
        end
        S_CMD_WAIT: if (reg_resp_valid) state <= S_START_ISSUE;

        // ── 5. BitFramingReg with StartSend=1 ──
        S_START_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b1;
            reg_req_addr  <= REG_BIT_FRAMING;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= {{1'b1, 4'b0, lat_tx_last_bits}, 248'd0};
            state         <= S_START_WAIT;
          end
        end
        S_START_WAIT: if (reg_resp_valid) state <= S_POLL_ISSUE;

        // ── 6. Poll ComIrqReg for RxIRq ──
        S_POLL_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b0;
            reg_req_addr  <= REG_COM_IRQ;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= 256'd0;
            state         <= S_POLL_WAIT;
          end
        end
        S_POLL_WAIT: begin
          if (reg_resp_valid) begin
            if (reg_resp_rdata[255:248] & IRQ_RX) state <= S_IDLE_CMD_ISSUE;  // got RxIRq, move on
            else state <= S_POLL_ISSUE;  // not yet, poll again
          end
        end

        // ── 7. CommandReg = Idle ──
        S_IDLE_CMD_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b1;
            reg_req_addr  <= REG_COMMAND;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= {CMD_IDLE, 248'd0};
            state         <= S_IDLE_CMD_WAIT;
          end
        end
        S_IDLE_CMD_WAIT: if (reg_resp_valid) state <= S_RDLVL_ISSUE;

        // ── 8. Read FIFOLevelReg ──
        S_RDLVL_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b0;
            reg_req_addr  <= REG_FIFO_LEVEL;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= 256'd0;
            state         <= S_RDLVL_WAIT;
          end
        end
        S_RDLVL_WAIT: begin
          if (reg_resp_valid) begin
            if (reg_resp_rdata[255:248] > 7'd32) fifo_level <= 6'd32;
            else fifo_level <= reg_resp_rdata[255:248];
            state <= S_RDFIFO_ISSUE;
          end
        end

        // ── 9. Read FIFO data ──
        S_RDFIFO_ISSUE: begin
          if (fifo_level == 6'd0) begin
            // Nothing to read
            trx_rx_len  <= 5'd0;
            trx_rx_data <= 256'd0;
            state       <= S_RDCTRL_ISSUE;
          end else if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b0;
            reg_req_addr  <= REG_FIFO_DATA;
            reg_req_len   <= fifo_level;
            reg_req_wdata <= 256'd0;
            state         <= S_RDFIFO_WAIT;
          end
        end
        S_RDFIFO_WAIT: begin
          if (reg_resp_valid) begin
            trx_rx_len  <= fifo_level;
            trx_rx_data <= reg_resp_rdata;
            state       <= S_RDCTRL_ISSUE;
          end
        end

        // ── 10. Read ControlReg (rx last bits) ──
        S_RDCTRL_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b0;
            reg_req_addr  <= REG_CONTROL;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= 256'd0;
            state         <= S_RDCTRL_WAIT;
          end
        end
        S_RDCTRL_WAIT: begin
          if (reg_resp_valid) begin
            trx_rx_last_bits <= reg_resp_rdata[248+:3];
            state            <= S_DONE;
          end
        end

        // ── 11. Signal done ──
        S_DONE: begin
          trx_done <= 1'b1;
          state    <= S_IDLE;
        end

        default: state <= S_IDLE;

      endcase
    end
  end

endmodule




