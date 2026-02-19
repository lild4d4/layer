// mfrc_top – MFRC522 top-level controller
//
// Replicates the behaviour of the Arduino main.ino reference:
//   1. Auto-init: soft reset, register configuration, antenna enable
//   2. Auto-poll: periodically send REQA (0x26) to detect cards
//   3. Transceive passthrough: external TX/RX interface for PICC commands
//      (ANTICOLL, SELECT, RATS, I-Blocks are driven by the layer above)
//
// Instantiates mfrc_reg_if internally for register-level SPI access.
// Connects to spi_arb as Client B (cs_sel=0 → MFRC522 / cs0).
//
// Status outputs:
//   ready        – 1 when idle and accepting TX commands
//   init_done    – latched high after auto-init completes
//   card_present – 1 after successful REQA (ATQA received)
//   atqa         – last received ATQA (16-bit)
//
// TX interface (from higher layer to card):
//   tx_valid, tx_ready, tx_len, tx_data, tx_last_bits
//
// RX interface (from card to higher layer):
//   rx_valid, rx_len, rx_data, rx_last_bits

module mfrc_top (
    input wire clk,
    input wire rst,

    // -- status outputs --
    output reg         ready,
    output reg         init_done,
    output reg         card_present,
    output reg  [15:0] atqa,

    // -- TX interface (to card) --
    input  wire         tx_valid,
    output reg          tx_ready,
    input  wire [  4:0] tx_len,        // byte count - 1
    input  wire [255:0] tx_data,       // payload (byte 0 = [255:248])
    input  wire [  2:0] tx_last_bits,  // valid bits in last byte (0=all 8)
    input  wire [  1:0] tx_kind,

    // -- RX interface (from card) --
    output reg          rx_valid,
    output reg  [  4:0] rx_len,        // byte count - 1
    output reg  [255:0] rx_data,       // payload (byte 0 = [255:248])
    output reg  [  2:0] rx_last_bits,

    // -- SPI arbiter interface (directly wired to spi_arb Client B) --
    output wire         spi_go,
    input  wire         spi_done,
    input  wire         spi_busy,
    output wire [255:0] spi_tx_data,
    input  wire [255:0] spi_rx_data,
    output wire [  5:0] spi_w_len,
    output wire [  5:0] spi_r_len
);

  // ===================================================================
  // Register interface instance
  // ===================================================================
  reg          reg_req_valid;
  wire         reg_req_ready;
  reg          reg_req_write;
  reg  [  5:0] reg_req_addr;
  reg  [  4:0] reg_req_len;
  reg  [255:0] reg_req_wdata;
  wire         reg_resp_valid;
  wire [255:0] reg_resp_rdata;
  wire         reg_resp_ok;

  mfrc_reg_if u_mfrc_reg_if (
      .clk       (clk),
      .rst       (rst),
      .req_valid (reg_req_valid),
      .req_ready (reg_req_ready),
      .req_write (reg_req_write),
      .req_addr  (reg_req_addr),
      .req_len   (reg_req_len),
      .req_wdata (reg_req_wdata),
      .resp_valid(reg_resp_valid),
      .resp_rdata(reg_resp_rdata),
      .resp_ok   (reg_resp_ok),
      .spi_go    (spi_go),
      .spi_done  (spi_done),
      .spi_busy  (spi_busy),
      .spi_w_len (spi_w_len),
      .spi_r_len (spi_r_len),
      .spi_tx_data(spi_tx_data),
      .spi_rx_data(spi_rx_data)
  );

  // ===================================================================
  // MFRC522 register addresses (matching Arduino defines)
  // ===================================================================
  localparam [5:0] R_COMMAND      = 6'h01,
                   R_COM_IRQ      = 6'h04,
                   R_DIV_IRQ      = 6'h05,
                   R_ERROR        = 6'h06,
                   R_FIFO_DATA    = 6'h09,
                   R_FIFO_LEVEL   = 6'h0A,
                   R_CONTROL      = 6'h0C,
                   R_BIT_FRAMING  = 6'h0D,
                   R_COLL         = 6'h0E,
                   R_MODE         = 6'h11,
                   R_TX_MODE      = 6'h12,
                   R_RX_MODE      = 6'h13,
                   R_TX_CONTROL   = 6'h14,
                   R_TX_ASK       = 6'h15,
                   R_CRC_RESULT_H = 6'h21,
                   R_CRC_RESULT_L = 6'h22,
                   R_MOD_WIDTH    = 6'h24,
                   R_T_MODE       = 6'h2A,
                   R_T_PRESCALER  = 6'h2B,
                   R_T_RELOAD_H   = 6'h2C,
                   R_T_RELOAD_L   = 6'h2D,
                   R_VERSION      = 6'h37;

  // MFRC522 commands
  localparam [7:0] CMD_IDLE       = 8'h00,
                   CMD_CALCCRC    = 8'h03,
                   CMD_TRANSCEIVE = 8'h0C,
                   CMD_SOFTRESET  = 8'h0F;

  // ComIrqReg bit masks
  localparam [7:0] IRQ_TIMER = 8'h01,
                   IRQ_ERR   = 8'h02,
                   IRQ_IDLE  = 8'h10,
                   IRQ_RX    = 8'h20,
                   IRQ_TX    = 8'h40;

  // ===================================================================
  // Main state machine
  // ===================================================================
  //
  // States are grouped by phase:
  //   INIT_*   – auto-initialization after reset
  //   POLL_*   – auto-poll for card presence (REQA)
  //   TRX_*    – transceive passthrough for external commands

  localparam [5:0]
    // Initialization sequence (matches Arduino setup())
    S_IDLE           = 6'd0,
    S_INIT_RESET     = 6'd1,   // Write CMD_SOFTRESET to CommandReg
    S_INIT_RESET_W   = 6'd2,   // Wait for resp
    S_INIT_RESET_RD  = 6'd3,   // Read CommandReg to check reset done
    S_INIT_RESET_CHK = 6'd4,   // Check if PowerDown bit cleared
    S_INIT_REG       = 6'd5,   // Write init registers (table-driven)
    S_INIT_REG_W     = 6'd6,   // Wait for resp
    S_INIT_ANT_RD    = 6'd7,   // Read TxControlReg
    S_INIT_ANT_CHK   = 6'd8,   // Check antenna bits
    S_INIT_ANT_WR    = 6'd9,   // Write TxControlReg with antenna on
    S_INIT_ANT_W     = 6'd10,  // Wait for resp
    S_INIT_DONE      = 6'd11,  // Done

    // Polling (matches PICC_IsNewCardPresent)
    S_POLL_SETUP     = 6'd12,  // Write TxModeReg etc.
    S_POLL_SETUP_W   = 6'd13,
    S_POLL_TRX_PREP  = 6'd14,  // Prepare transceive for REQA
    S_POLL_TRX_PREP_W= 6'd15,
    S_POLL_WAIT      = 6'd16,  // Waiting for result from transceive engine

    // Transceive engine (shared by poll and external TX)
    S_TRX_IDLE_CMD   = 6'd17,  // wrReg(CommandReg, CMD_IDLE)
    S_TRX_IDLE_W     = 6'd18,
    S_TRX_CLR_IRQ    = 6'd19,  // wrReg(ComIrqReg, 0x7F)
    S_TRX_CLR_W      = 6'd20,
    S_TRX_FLUSH      = 6'd21,  // wrReg(FIFOLevelReg, 0x80)
    S_TRX_FLUSH_W    = 6'd22,
    S_TRX_FIFO_LOAD  = 6'd23,  // wrReg(FIFODataReg, byte[i])
    S_TRX_FIFO_W     = 6'd24,
    S_TRX_BITFRAME   = 6'd25,  // wrReg(BitFramingReg, validBits)
    S_TRX_BITFRAME_W = 6'd26,
    S_TRX_START_CMD  = 6'd27,  // wrReg(CommandReg, CMD_TRANSCEIVE)
    S_TRX_START_W    = 6'd28,
    S_TRX_RD_BF      = 6'd29,  // rdReg(BitFramingReg)
    S_TRX_RD_BF_W    = 6'd30,
    S_TRX_SET_START  = 6'd31,  // wrReg(BitFramingReg, bf | 0x80)
    S_TRX_SET_START_W = 6'd32,
    S_TRX_POLL_IRQ   = 6'd33,  // rdReg(ComIrqReg)
    S_TRX_POLL_IRQ_W = 6'd34,
    S_TRX_CHK_ERR    = 6'd35,  // rdReg(ErrorReg)
    S_TRX_CHK_ERR_W  = 6'd36,
    S_TRX_RD_FIFO_LEN = 6'd37, // rdReg(FIFOLevelReg)
    S_TRX_RD_FIFO_LEN_W = 6'd38,
    S_TRX_RD_FIFO    = 6'd39,  // rdReg(FIFODataReg) × N
    S_TRX_RD_FIFO_W  = 6'd40,
    S_TRX_RD_CTRL    = 6'd41,  // rdReg(ControlReg) for RxLastBits
    S_TRX_RD_CTRL_W  = 6'd42,
    S_TRX_DONE       = 6'd43,  // Signal result

    // External transceive (passthrough)
    S_EXT_ACCEPT     = 6'd44,  // Accept external TX request
    S_EXT_DONE       = 6'd45,  // Signal RX result

    // Delay between polls
    S_POLL_DELAY     = 6'd46,

    // RATS-specific pre/post register sequence
    S_PRE_RATS_TXMODE_WR      = 6'd47,
    S_PRE_RATS_TXMODE_WR_WAIT = 6'd48,
    S_RATS_PREP               = 6'd49,
    S_RATS_PREP_WAIT          = 6'd50,
    S_POST_RATS_RXMODE_WR     = 6'd51,
    S_POST_RATS_RXMODE_WR_WAIT = 6'd52,
    S_POST_RATS_WR            = 6'd53,
    S_POST_RATS_WR_WAIT       = 6'd54,
    S_POST_RATS_TMODE_WR      = 6'd55,
    S_POST_RATS_TMODE_WR_WAIT = 6'd56,
    S_POST_RATS_TPRES_WR      = 6'd57,
    S_POST_RATS_TPRES_WR_WAIT = 6'd58;

  (* MARK_DEBUG = "TRUE" *) reg [5:0] state;

  // ===================================================================
  // Transceive working registers
  // ===================================================================
  reg [255:0] trx_tx_data;     // data to send to card
  reg [  4:0] trx_tx_len;      // bytes - 1
  reg [  2:0] trx_tx_last_bits;// valid bits in last byte
  reg [  1:0] trx_kind;        // command kind (normal/rats)
  reg [255:0] trx_rx_data;     // data received from card
  reg [  4:0] trx_rx_len;      // bytes received - 1
  reg [  2:0] trx_rx_last_bits;
  reg         trx_ok;          // 1 = success
  reg         trx_is_poll;     // 1 = internal poll, 0 = external

  reg [  4:0] fifo_idx;        // FIFO byte index for load/read
  reg [  4:0] fifo_cnt;        // FIFO byte count from MFRC522

  // ===================================================================
  // Init register table
  // ===================================================================
  // Matches Arduino setup() register writes exactly:
  //   TxModeReg=0x00, RxModeReg=0x00, ModWidthReg=0x26,
  //   TModeReg=0x80, TPrescalerReg=0xA9,
  //   TReloadRegH=0x03, TReloadRegL=0xE8,
  //   TxASKReg=0x40, ModeReg=0x3D
  localparam INIT_REG_COUNT = 9;

  // Pack as {addr[5:0], data[7:0]} = 14 bits
  wire [13:0] init_table [0:INIT_REG_COUNT-1];
  assign init_table[0] = {R_TX_MODE,     8'h00};
  assign init_table[1] = {R_RX_MODE,     8'h00};
  assign init_table[2] = {R_MOD_WIDTH,   8'h26};
  assign init_table[3] = {R_T_MODE,      8'h80};
  assign init_table[4] = {R_T_PRESCALER, 8'hA9};
  assign init_table[5] = {R_T_RELOAD_H,  8'h03};
  assign init_table[6] = {R_T_RELOAD_L,  8'hE8};
  assign init_table[7] = {R_TX_ASK,      8'h40};
  assign init_table[8] = {R_MODE,        8'h3D};

  reg [3:0] init_idx;

  // ===================================================================
  // Poll setup register table
  // ===================================================================
  // Before REQA: TxModeReg=0x00, RxModeReg=0x00, ModWidthReg=0x26
  // (Matches PICC_IsNewCardPresent)
  localparam POLL_SETUP_COUNT = 4;

  wire [13:0] poll_setup_table [0:POLL_SETUP_COUNT-1];
  assign poll_setup_table[0] = {R_TX_MODE,   8'h00};
  assign poll_setup_table[1] = {R_RX_MODE,   8'h00};
  assign poll_setup_table[2] = {R_MOD_WIDTH, 8'h26};
  assign poll_setup_table[3] = {R_COLL,      8'h80};  // CollReg = 0x80

  reg [2:0] poll_setup_idx;

  // ===================================================================
  // Poll delay counter
  // ===================================================================
  localparam [19:0] POLL_DELAY = 20'd50_000;  // ~500us at 100MHz
  reg [19:0] delay_ctr;

  // ===================================================================
  // IRQ polling timeout counter
  // ===================================================================
  localparam [19:0] IRQ_TIMEOUT = 20'd500_000;  // 5ms at 100MHz
  reg [19:0] irq_timeout_ctr;

  // ===================================================================
  // Soft reset wait counter
  // ===================================================================
  reg [15:0] reset_wait_ctr;

  // ===================================================================
  // Helper: write a single register byte via reg_if
  // ===================================================================
  task automatic issue_write(input [5:0] addr, input [7:0] data);
    begin
      reg_req_valid <= 1'b1;
      reg_req_write <= 1'b1;
      reg_req_addr  <= addr;
      reg_req_len   <= 5'd0;
      reg_req_wdata <= {data, 248'd0};
    end
  endtask

  // Helper: read a single register byte via reg_if
  task automatic issue_read(input [5:0] addr);
    begin
      reg_req_valid <= 1'b1;
      reg_req_write <= 1'b0;
      reg_req_addr  <= addr;
      reg_req_len   <= 5'd0;
      reg_req_wdata <= 256'd0;
    end
  endtask

  // Extracted response byte
  wire [7:0] resp_byte = reg_resp_rdata[255:248];

  // ===================================================================
  // Main FSM
  // ===================================================================
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state            <= S_IDLE;
      ready            <= 1'b0;
      init_done        <= 1'b0;
      card_present     <= 1'b0;
      atqa             <= 16'd0;
      tx_ready         <= 1'b0;
      rx_valid         <= 1'b0;
      rx_len           <= 5'd0;
      rx_data          <= 256'd0;
      rx_last_bits     <= 3'd0;

      reg_req_valid    <= 1'b0;
      reg_req_write    <= 1'b0;
      reg_req_addr     <= 6'd0;
      reg_req_len      <= 5'd0;
      reg_req_wdata    <= 256'd0;

      trx_tx_data      <= 256'd0;
      trx_tx_len       <= 5'd0;
      trx_tx_last_bits <= 3'd0;
      trx_kind         <= 2'd0;
      trx_rx_data      <= 256'd0;
      trx_rx_len       <= 5'd0;
      trx_rx_last_bits <= 3'd0;
      trx_ok           <= 1'b0;
      trx_is_poll      <= 1'b0;

      fifo_idx         <= 5'd0;
      fifo_cnt         <= 5'd0;
      init_idx         <= 4'd0;
      poll_setup_idx   <= 3'd0;
      delay_ctr        <= 20'd0;
      irq_timeout_ctr  <= 20'd0;
      reset_wait_ctr   <= 16'd0;
    end else begin
      // Auto-clear pulses
      reg_req_valid <= 1'b0;
      rx_valid      <= 1'b0;

      case (state)

        // ============================================================
        // IDLE – start init on boot
        // ============================================================
        S_IDLE: begin
          state <= S_INIT_RESET;
        end

        // ============================================================
        // INIT phase: Soft Reset
        // ============================================================
        // Arduino: wrReg(CommandReg, 0x0F)
        S_INIT_RESET: begin
          if (reg_req_ready) begin
            issue_write(R_COMMAND, CMD_SOFTRESET);
            state <= S_INIT_RESET_W;
          end
        end

        S_INIT_RESET_W: begin
          if (reg_resp_valid) begin
            reset_wait_ctr <= 16'd5000;  // wait ~50us for reset
            state <= S_INIT_RESET_RD;
          end
        end

        // Arduino: while((rdReg(CommandReg) & (1<<4)) != 0)
        S_INIT_RESET_RD: begin
          if (reset_wait_ctr != 0) begin
            reset_wait_ctr <= reset_wait_ctr - 16'd1;
          end else if (reg_req_ready) begin
            issue_read(R_COMMAND);
            state <= S_INIT_RESET_CHK;
          end
        end

        S_INIT_RESET_CHK: begin
          if (reg_resp_valid) begin
            if (resp_byte[4] == 1'b0) begin
              // Reset complete, proceed to register init
              init_idx <= 4'd0;
              state    <= S_INIT_REG;
            end else begin
              // Still resetting, try again
              reset_wait_ctr <= 16'd5000;
              state <= S_INIT_RESET_RD;
            end
          end
        end

        // ============================================================
        // INIT phase: Register configuration (table-driven)
        // ============================================================
        S_INIT_REG: begin
          if (reg_req_ready) begin
            if (init_idx < INIT_REG_COUNT) begin
              issue_write(init_table[init_idx][13:8],
                         init_table[init_idx][7:0]);
              state <= S_INIT_REG_W;
            end else begin
              // All init registers written, check antenna
              state <= S_INIT_ANT_RD;
            end
          end
        end

        S_INIT_REG_W: begin
          if (reg_resp_valid) begin
            init_idx <= init_idx + 4'd1;
            state    <= S_INIT_REG;
          end
        end

        // ============================================================
        // INIT phase: Antenna enable
        // ============================================================
        // Arduino: tc = rdReg(TxControlReg); if ((tc & 0x03) != 0x03) wrReg(...)
        S_INIT_ANT_RD: begin
          if (reg_req_ready) begin
            issue_read(R_TX_CONTROL);
            state <= S_INIT_ANT_CHK;
          end
        end

        S_INIT_ANT_CHK: begin
          if (reg_resp_valid) begin
            if ((resp_byte & 8'h03) != 8'h03) begin
              // Need to enable antenna
              state <= S_INIT_ANT_WR;
            end else begin
              // Antenna already on
              state <= S_INIT_DONE;
            end
          end
        end

        S_INIT_ANT_WR: begin
          if (reg_req_ready) begin
            issue_write(R_TX_CONTROL, resp_byte | 8'h03);
            state <= S_INIT_ANT_W;
          end
        end

        S_INIT_ANT_W: begin
          if (reg_resp_valid) begin
            state <= S_INIT_DONE;
          end
        end

        // ============================================================
        // INIT complete → start polling
        // ============================================================
        S_INIT_DONE: begin
          init_done <= 1'b1;
          ready     <= 1'b1;
          tx_ready  <= 1'b1;
          poll_setup_idx <= 3'd0;
          state     <= S_POLL_SETUP;
        end

        // ============================================================
        // POLL phase: Setup registers before REQA
        // ============================================================
        // Arduino: wrReg(TxModeReg, 0x00); wrReg(RxModeReg, 0x00);
        //          wrReg(ModWidthReg, 0x26);
        S_POLL_SETUP: begin
          // Check for external TX request (higher priority)
          if (tx_valid && tx_ready) begin
            state <= S_EXT_ACCEPT;
          end else if (reg_req_ready) begin
            if (poll_setup_idx < POLL_SETUP_COUNT) begin
              issue_write(poll_setup_table[poll_setup_idx][13:8],
                         poll_setup_table[poll_setup_idx][7:0]);
              state <= S_POLL_SETUP_W;
            end else begin
              // Setup done, prepare REQA transceive
              state <= S_POLL_TRX_PREP;
            end
          end
        end

        S_POLL_SETUP_W: begin
          if (reg_resp_valid) begin
            poll_setup_idx <= poll_setup_idx + 3'd1;
            state          <= S_POLL_SETUP;
          end
        end

        // ============================================================
        // POLL: Prepare REQA transceive
        // ============================================================
        S_POLL_TRX_PREP: begin
          trx_tx_data      <= {8'h26, 248'd0};  // REQA command
          trx_tx_len       <= 5'd0;              // 1 byte
          trx_tx_last_bits <= 3'd7;              // 7-bit frame
          trx_kind         <= 2'd0;
          trx_is_poll      <= 1'b1;
          trx_ok           <= 1'b0;
          fifo_idx         <= 5'd0;
          trx_rx_data      <= 256'd0;
          trx_rx_len       <= 5'd0;
          trx_rx_last_bits <= 3'd0;
          ready            <= 1'b0;
          tx_ready         <= 1'b0;
          state            <= S_TRX_IDLE_CMD;
        end

        S_POLL_WAIT: begin
          // Return from transceive engine with result
          if (trx_ok) begin
            // ATQA received (2 bytes: trx_rx_data[255:240])
            card_present <= 1'b1;
            atqa         <= trx_rx_data[255:240];
          end else begin
            card_present <= 1'b0;
          end
          ready    <= 1'b1;
          tx_ready <= 1'b1;
          delay_ctr <= POLL_DELAY;
          state     <= S_POLL_DELAY;
        end

        // ============================================================
        // POLL delay between attempts
        // ============================================================
        S_POLL_DELAY: begin
          // Check for external TX request (higher priority)
          if (tx_valid && tx_ready) begin
            state <= S_EXT_ACCEPT;
          end else if (delay_ctr == 0) begin
            poll_setup_idx <= 3'd0;
            state          <= S_POLL_SETUP;
          end else begin
            delay_ctr <= delay_ctr - 20'd1;
          end
        end

        // ============================================================
        // External transceive: accept TX request
        // ============================================================
        S_EXT_ACCEPT: begin
          trx_tx_data      <= tx_data;
          trx_tx_len       <= tx_len;
          trx_tx_last_bits <= tx_last_bits;
          trx_kind         <= tx_kind;
          trx_is_poll      <= 1'b0;
          trx_ok           <= 1'b0;
          fifo_idx         <= 5'd0;
          trx_rx_data      <= 256'd0;
          trx_rx_len       <= 5'd0;
          trx_rx_last_bits <= 3'd0;
          ready            <= 1'b0;
          tx_ready         <= 1'b0;
          if (tx_kind == 2'd1)
            state <= S_PRE_RATS_TXMODE_WR;
          else
            state <= S_TRX_IDLE_CMD;
        end

        S_EXT_DONE: begin
          // Signal RX result to external layer
          rx_valid     <= 1'b1;
          rx_len       <= trx_rx_len;
          rx_data      <= trx_rx_data;
          rx_last_bits <= trx_rx_last_bits;
          ready        <= 1'b1;
          tx_ready     <= 1'b1;
          delay_ctr    <= POLL_DELAY;
          state        <= S_POLL_DELAY;
        end

        // ============================================================
        // RATS-specific register setup/restore (Arduino doRATS)
        // ============================================================
        S_PRE_RATS_TXMODE_WR: begin
          if (reg_req_ready) begin
            issue_write(R_TX_MODE, 8'h80);
            state <= S_PRE_RATS_TXMODE_WR_WAIT;
          end
        end

        S_PRE_RATS_TXMODE_WR_WAIT: begin
          if (reg_resp_valid)
            state <= S_RATS_PREP;
        end

        S_RATS_PREP: begin
          if (reg_req_ready) begin
            issue_write(R_RX_MODE, 8'h00);
            state <= S_RATS_PREP_WAIT;
          end
        end

        S_RATS_PREP_WAIT: begin
          if (reg_resp_valid)
            state <= S_TRX_IDLE_CMD;
        end

        S_POST_RATS_RXMODE_WR: begin
          if (reg_req_ready) begin
            issue_write(R_RX_MODE, 8'h80);
            state <= S_POST_RATS_RXMODE_WR_WAIT;
          end
        end

        S_POST_RATS_RXMODE_WR_WAIT: begin
          if (reg_resp_valid)
            state <= S_POST_RATS_WR;
        end

        S_POST_RATS_WR: begin
          if (reg_req_ready) begin
            issue_write(R_BIT_FRAMING, 8'h00);
            state <= S_POST_RATS_WR_WAIT;
          end
        end

        S_POST_RATS_WR_WAIT: begin
          if (reg_resp_valid)
            state <= S_POST_RATS_TMODE_WR;
        end

        S_POST_RATS_TMODE_WR: begin
          if (reg_req_ready) begin
            issue_write(R_T_MODE, 8'h8D);
            state <= S_POST_RATS_TMODE_WR_WAIT;
          end
        end

        S_POST_RATS_TMODE_WR_WAIT: begin
          if (reg_resp_valid)
            state <= S_POST_RATS_TPRES_WR;
        end

        S_POST_RATS_TPRES_WR: begin
          if (reg_req_ready) begin
            issue_write(R_T_PRESCALER, 8'h3E);
            state <= S_POST_RATS_TPRES_WR_WAIT;
          end
        end

        S_POST_RATS_TPRES_WR_WAIT: begin
          if (reg_resp_valid)
            state <= S_EXT_DONE;
        end

        // ============================================================
        // TRANSCEIVE ENGINE
        // ============================================================
        // Mirrors PCD_TransceiveData() from Arduino:
        //   1. wrReg(CommandReg, CMD_IDLE)
        //   2. wrReg(ComIrqReg, 0x7F)    – clear all IRQ flags
        //   3. wrReg(FIFOLevelReg, 0x80)  – flush FIFO
        //   4. wrReg(FIFODataReg, byte_i) – load TX bytes
        //   5. wrReg(BitFramingReg, valid_bits)
        //   6. wrReg(CommandReg, CMD_TRANSCEIVE)
        //   7. rdReg(BitFramingReg) → bf
        //   8. wrReg(BitFramingReg, bf | 0x80)  – start send
        //   9. Poll rdReg(ComIrqReg) until RxIRq|IdleIRq or TimerIRq
        //  10. rdReg(ErrorReg) – check errors
        //  11. rdReg(FIFOLevelReg) – get RX byte count
        //  12. rdReg(FIFODataReg) × N – read RX bytes
        //  13. rdReg(ControlReg) – get RxLastBits

        // Step 1: wrReg(CommandReg, CMD_IDLE)
        S_TRX_IDLE_CMD: begin
          if (reg_req_ready) begin
            issue_write(R_COMMAND, CMD_IDLE);
            state <= S_TRX_IDLE_W;
          end
        end
        S_TRX_IDLE_W: begin
          if (reg_resp_valid) state <= S_TRX_CLR_IRQ;
        end

        // Step 2: wrReg(ComIrqReg, 0x7F) – clear IRQ flags
        S_TRX_CLR_IRQ: begin
          if (reg_req_ready) begin
            issue_write(R_COM_IRQ, 8'h7F);
            state <= S_TRX_CLR_W;
          end
        end
        S_TRX_CLR_W: begin
          if (reg_resp_valid) state <= S_TRX_FLUSH;
        end

        // Step 3: wrReg(FIFOLevelReg, 0x80) – flush
        S_TRX_FLUSH: begin
          if (reg_req_ready) begin
            issue_write(R_FIFO_LEVEL, 8'h80);
            state <= S_TRX_FLUSH_W;
          end
        end
        S_TRX_FLUSH_W: begin
          if (reg_resp_valid) begin
            fifo_idx <= 5'd0;
            state    <= S_TRX_FIFO_LOAD;
          end
        end

        // Step 4: wrReg(FIFODataReg, byte[i]) for each TX byte
        S_TRX_FIFO_LOAD: begin
          if (reg_req_ready) begin
            if (fifo_idx <= trx_tx_len) begin
              issue_write(R_FIFO_DATA, trx_tx_data[255 - fifo_idx*8 -: 8]);
              state <= S_TRX_FIFO_W;
            end else begin
              // All bytes loaded
              state <= S_TRX_BITFRAME;
            end
          end
        end
        S_TRX_FIFO_W: begin
          if (reg_resp_valid) begin
            fifo_idx <= fifo_idx + 5'd1;
            state    <= S_TRX_FIFO_LOAD;
          end
        end

        // Step 5: wrReg(BitFramingReg, validBits)
        // Arduino: bf = (rxAlign << 4) + validBits
        // For our usage rxAlign is always 0
        S_TRX_BITFRAME: begin
          if (reg_req_ready) begin
            issue_write(R_BIT_FRAMING, {5'b0, trx_tx_last_bits});
            state <= S_TRX_BITFRAME_W;
          end
        end
        S_TRX_BITFRAME_W: begin
          if (reg_resp_valid) state <= S_TRX_START_CMD;
        end

        // Step 6: wrReg(CommandReg, CMD_TRANSCEIVE)
        S_TRX_START_CMD: begin
          if (reg_req_ready) begin
            issue_write(R_COMMAND, CMD_TRANSCEIVE);
            state <= S_TRX_START_W;
          end
        end
        S_TRX_START_W: begin
          if (reg_resp_valid) state <= S_TRX_RD_BF;
        end

        // Step 7: rdReg(BitFramingReg)
        S_TRX_RD_BF: begin
          if (reg_req_ready) begin
            issue_read(R_BIT_FRAMING);
            state <= S_TRX_RD_BF_W;
          end
        end
        S_TRX_RD_BF_W: begin
          if (reg_resp_valid) state <= S_TRX_SET_START;
        end

        // Step 8: wrReg(BitFramingReg, bf | 0x80) – StartSend
        S_TRX_SET_START: begin
          if (reg_req_ready) begin
            issue_write(R_BIT_FRAMING, resp_byte | 8'h80);
            irq_timeout_ctr <= IRQ_TIMEOUT;
            state <= S_TRX_SET_START_W;
          end
        end
        S_TRX_SET_START_W: begin
          if (reg_resp_valid) state <= S_TRX_POLL_IRQ;
        end

        // Step 9: Poll ComIrqReg
        S_TRX_POLL_IRQ: begin
          if (reg_req_ready) begin
            if (irq_timeout_ctr == 0) begin
              // Software timeout
              trx_ok <= 1'b0;
              state  <= S_TRX_DONE;
            end else begin
              issue_read(R_COM_IRQ);
              irq_timeout_ctr <= irq_timeout_ctr - 20'd1;
              state <= S_TRX_POLL_IRQ_W;
            end
          end
        end

        S_TRX_POLL_IRQ_W: begin
          if (reg_resp_valid) begin
            // Check IRQ bits (Arduino: if (n & 0x30) break)
            if (resp_byte & (IRQ_RX | IRQ_IDLE)) begin
              // RxIRq or IdleIRq set → transceive complete
              state <= S_TRX_CHK_ERR;
            end else if (resp_byte & IRQ_TIMER) begin
              // TimerIRq → timeout, no card response
              trx_ok <= 1'b0;
              state  <= S_TRX_DONE;
            end else begin
              // Keep polling
              state <= S_TRX_POLL_IRQ;
            end
          end
        end

        // Step 10: rdReg(ErrorReg) – check for errors
        S_TRX_CHK_ERR: begin
          if (reg_req_ready) begin
            issue_read(R_ERROR);
            state <= S_TRX_CHK_ERR_W;
          end
        end
        S_TRX_CHK_ERR_W: begin
          if (reg_resp_valid) begin
            // Arduino: if (rdReg(ErrorReg) & 0x13) return 0
            if (resp_byte & 8'h13) begin
              trx_ok <= 1'b0;
              state  <= S_TRX_DONE;
            end else begin
              state <= S_TRX_RD_FIFO_LEN;
            end
          end
        end

        // Step 11: rdReg(FIFOLevelReg) – get byte count
        S_TRX_RD_FIFO_LEN: begin
          if (reg_req_ready) begin
            issue_read(R_FIFO_LEVEL);
            state <= S_TRX_RD_FIFO_LEN_W;
          end
        end
        S_TRX_RD_FIFO_LEN_W: begin
          if (reg_resp_valid) begin
            fifo_cnt <= resp_byte[4:0];
            fifo_idx <= 5'd0;
            trx_rx_data <= 256'd0;
            if (resp_byte[4:0] == 5'd0) begin
              // No data received
              trx_ok     <= 1'b0;
              trx_rx_len <= 5'd0;
              state      <= S_TRX_DONE;
            end else begin
              trx_rx_len <= resp_byte[4:0] - 5'd1;
              state      <= S_TRX_RD_FIFO;
            end
          end
        end

        // Step 12: rdReg(FIFODataReg) × N
        S_TRX_RD_FIFO: begin
          if (reg_req_ready) begin
            if (fifo_idx < fifo_cnt) begin
              issue_read(R_FIFO_DATA);
              state <= S_TRX_RD_FIFO_W;
            end else begin
              // All bytes read
              state <= S_TRX_RD_CTRL;
            end
          end
        end
        S_TRX_RD_FIFO_W: begin
          if (reg_resp_valid) begin
            trx_rx_data[255 - fifo_idx*8 -: 8] <= resp_byte;
            fifo_idx <= fifo_idx + 5'd1;
            state    <= S_TRX_RD_FIFO;
          end
        end

        // Step 13: rdReg(ControlReg) for RxLastBits
        S_TRX_RD_CTRL: begin
          if (reg_req_ready) begin
            issue_read(R_CONTROL);
            state <= S_TRX_RD_CTRL_W;
          end
        end
        S_TRX_RD_CTRL_W: begin
          if (reg_resp_valid) begin
            trx_rx_last_bits <= resp_byte[2:0];
            trx_ok           <= 1'b1;
            state            <= S_TRX_DONE;
          end
        end

        // ============================================================
        // TRANSCEIVE DONE: route result to poll or external handler
        // ============================================================
        S_TRX_DONE: begin
          if (trx_is_poll) begin
            state <= S_POLL_WAIT;
          end else if (trx_kind == 2'd1 && trx_ok) begin
            state <= S_POST_RATS_RXMODE_WR;
          end else begin
            state <= S_EXT_DONE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
