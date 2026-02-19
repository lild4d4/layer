// mfrc_core – simplified MFRC522 transceive controller
//
// Fully linear FSM: each state does one register operation then advances.
// No timeout counting or error analysis — higher layers handle that
// by pulling a hard reset and retrying if needed.
//
// Happy path:
//   1. Write CommandReg = Idle (stop any active command)
//   2. Write ComIrqReg = 0x7F (clear all interrupt flags)
//   3. Flush FIFO
//   4. Write BitFramingReg (tx last bits)
//   5. Write TX data to FIFO
//   6. Write CommandReg = Transceive
//   7. Write BitFramingReg with StartSend
//   8. Poll ComIrqReg until RxIRq or IdleIRq (or TimerIRq for timeout)
//   9. Write CommandReg = Idle
//  10. Read FIFOLevelReg
//  11. Read FIFO data
//  12. Read ControlReg (rx last bits)
//  13. Done
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
    output reg         trx_timeout,      // TimerIRq fired (no card response)
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
  localparam logic [5:0] REG_COMMAND = 6'h01;
  localparam logic [5:0] REG_COM_IRQ = 6'h04;
  localparam logic [5:0] REG_FIFO_DATA = 6'h09;
  localparam logic [5:0] REG_FIFO_LEVEL = 6'h0A;
  localparam logic [5:0] REG_CONTROL = 6'h0C;
  localparam logic [5:0] REG_BIT_FRAMING = 6'h0D;

  // ── Constants ──
  localparam logic [7:0] CMD_IDLE = 8'h00;
  localparam logic [7:0] CMD_TRANSCEIVE = 8'h0C;
  localparam logic [7:0] IRQ_RX = 8'h20;  // RxIRq (bit 5)
  localparam logic [7:0] IRQ_IDLE = 8'h10;  // IdleIRq (bit 4)
  localparam logic [7:0] IRQ_TIMER = 8'h01;  // TimerIRq (bit 0)
  localparam logic [7:0] IRQ_CLEAR_ALL = 8'h7F;  // Clear all interrupt flags
  localparam logic [7:0] FIFO_FLUSH = 8'h80;

  // ── FSM states (fully linear) ──
  typedef enum logic [4:0] {
    S_IDLE           = 5'd0,
    S_STOP_ISSUE     = 5'd1,   // Step 1: CommandReg = Idle
    S_STOP_WAIT      = 5'd2,
    S_CLRIRQ_ISSUE   = 5'd3,   // Step 2: Clear ComIrqReg
    S_CLRIRQ_WAIT    = 5'd4,
    S_FLUSH_ISSUE    = 5'd5,   // Step 3: Flush FIFO
    S_FLUSH_WAIT     = 5'd6,
    S_BITFR_ISSUE    = 5'd7,   // Step 4: BitFramingReg
    S_BITFR_WAIT     = 5'd8,
    S_FIFOWR_ISSUE   = 5'd9,   // Step 5: Write TX data
    S_FIFOWR_WAIT    = 5'd10,
    S_CMD_ISSUE      = 5'd11,  // Step 6: CommandReg = Transceive
    S_CMD_WAIT       = 5'd12,
    S_START_ISSUE    = 5'd13,  // Step 7: StartSend
    S_START_WAIT     = 5'd14,
    S_POLL_ISSUE     = 5'd15,  // Step 8: Poll ComIrqReg
    S_POLL_WAIT      = 5'd16,
    S_IDLE_CMD_ISSUE = 5'd17,  // Step 9: CommandReg = Idle
    S_IDLE_CMD_WAIT  = 5'd18,
    S_RDLVL_ISSUE    = 5'd19,  // Step 10: Read FIFOLevelReg
    S_RDLVL_WAIT     = 5'd20,
    S_RDFIFO_ISSUE   = 5'd21,  // Step 11: Read FIFO data
    S_RDFIFO_WAIT    = 5'd22,
    S_RDCTRL_ISSUE   = 5'd23,  // Step 12: Read ControlReg
    S_RDCTRL_WAIT    = 5'd24,
    S_DONE           = 5'd25   // Step 13: Done
  } state_t;

  (* MARK_DEBUG = "TRUE" *)state_t         state;

  // Latched request
  reg     [  4:0] lat_tx_len;
  reg     [255:0] lat_tx_data;
  reg     [  2:0] lat_tx_last_bits;
  reg     [  4:0] fifo_level;
  reg             fifo_empty;
  reg             lat_timeout;


  assign trx_ready = (state == S_IDLE);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state            <= S_IDLE;
      reg_req_valid    <= 1'b0;
      reg_req_write    <= 1'b0;
      reg_req_addr     <= 6'd0;
      reg_req_len      <= 5'd0;
      reg_req_wdata    <= 256'd0;
      trx_done         <= 1'b0;
      trx_timeout      <= 1'b0;
      trx_rx_len       <= 5'd0;
      trx_rx_data      <= 256'd0;
      trx_rx_last_bits <= 3'd0;
      fifo_level       <= 5'd0;
      lat_tx_len       <= 5'd0;
      lat_tx_data      <= 256'd0;
      lat_tx_last_bits <= 3'd0;
      lat_timeout      <= 1'b0;
    end else begin
      reg_req_valid <= 1'b0;
      trx_done      <= 1'b0;

      case (state)

        // ── IDLE: latch request ──
        S_IDLE: begin
          trx_timeout <= 1'b0;
          if (trx_valid) begin
            lat_tx_len       <= trx_tx_len;
            lat_tx_data      <= trx_tx_data;
            lat_tx_last_bits <= trx_tx_last_bits;
            fifo_level       <= 5'd0;
            lat_timeout      <= 1'b0;
            state            <= S_STOP_ISSUE;
          end
        end

        // ── Step 1: CommandReg = Idle (stop any active command) ──
        S_STOP_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b1;
            reg_req_addr  <= REG_COMMAND;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= {CMD_IDLE, 248'd0};
            state         <= S_STOP_WAIT;
          end
        end
        S_STOP_WAIT: if (reg_resp_valid) state <= S_CLRIRQ_ISSUE;

        // ── Step 2: Clear ComIrqReg (all interrupt flags) ──
        S_CLRIRQ_ISSUE: begin
          if (reg_req_ready) begin
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b1;
            reg_req_addr  <= REG_COM_IRQ;
            reg_req_len   <= 5'd0;
            reg_req_wdata <= {IRQ_CLEAR_ALL, 248'd0};
            state         <= S_CLRIRQ_WAIT;
          end
        end
        S_CLRIRQ_WAIT: if (reg_resp_valid) state <= S_FLUSH_ISSUE;

        // ── Step 3: Flush FIFO ──
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

        // ── Step 4: BitFramingReg (tx last bits, StartSend=0) ──
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

        // ── Step 5: Write TX data to FIFO ──
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

        // ── Step 6: CommandReg = Transceive ──
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

        // ── Step 7: BitFramingReg with StartSend=1 ──
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

        // ── Step 8: Poll ComIrqReg for RxIRq, IdleIRq, or TimerIRq ──
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
            // Check for completion: RxIRq or IdleIRq
            if (reg_resp_rdata[255:248] & (IRQ_RX | IRQ_IDLE)) begin
              state <= S_IDLE_CMD_ISSUE;
            end  // Check for timeout: TimerIRq
            else if (reg_resp_rdata[255:248] & IRQ_TIMER) begin
              lat_timeout <= 1'b1;
              state       <= S_IDLE_CMD_ISSUE;
            end  // Not yet, poll again
            else begin
              state <= S_POLL_ISSUE;
            end
          end
        end

        // ── Step 9: CommandReg = Idle ──
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

        // ── Step 10: Read FIFOLevelReg ──
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
          fifo_empty <= (reg_resp_rdata[255:248] == 8'd0);

          if (reg_resp_valid) begin
            if (reg_resp_rdata[255:248] > 8'd32) begin
              fifo_level <= 5'd31;  // 31 = 32 bytes in your encoding
              state      <= S_RDFIFO_ISSUE;
            end else begin
              fifo_level <= reg_resp_rdata[252:248] - 5'd1;  // convert count→len encoding
              state      <= S_RDFIFO_ISSUE;
            end
          end
        end

        // ── Step 11: Read FIFO data ──
        S_RDFIFO_ISSUE: begin
          // Skip read if FIFO is empty or timeout occurred
          if (lat_timeout || fifo_empty) begin
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
            trx_rx_len  <= fifo_level + 5'd1;
            trx_rx_data <= reg_resp_rdata;
            state       <= S_RDCTRL_ISSUE;
          end
        end

        // ── Step 12: Read ControlReg (rx last bits) ──
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
            trx_rx_last_bits <= reg_resp_rdata[250:248];  // Bits [2:0] of ControlReg
            state            <= S_DONE;
          end
        end

        // ── Step 13: Signal done ──
        S_DONE: begin
          trx_done    <= 1'b1;
          trx_timeout <= lat_timeout;
          state       <= S_IDLE;
        end

        default: state <= S_IDLE;

      endcase
    end
  end

endmodule




