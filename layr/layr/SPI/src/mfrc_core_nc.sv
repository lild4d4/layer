// mfrc_core – MFRC522 "command plane" controller
//
// Sits above mfrc_reg_if and provides a transceive() primitive.
// This module no longer instantiates mfrc_reg_if; instead it exposes
// the mfrc_reg_if request/response interface so multiple clients can
// share a single mfrc_reg_if via an arbiter.
//
// Length encoding follows mfrc_reg_if: 5-bit, 0 = 1 byte, 31 = 32 bytes.
//
// NOTE: trx_timeout_cycles counts the number of SPI poll transactions
// issued against ComIrqReg, NOT wall-clock cycles.  Each "tick"
// corresponds to one full SPI register-read round-trip.

module mfrc_core (
    input  wire          clk,
    input  wire          rst,           // active-high, same as mfrc_reg_if

    // ── Transceive request ──
    input  wire          trx_valid,
    output wire          trx_ready,
    input  wire [4:0]    trx_tx_len,          // 0..31 → 1..32 bytes
    input  wire [255:0]  trx_tx_data,         // byte0 at [255:248]
    input  wire [2:0]    trx_tx_last_bits,    // 0 for full bytes, 7 for REQA/WUPA
    input  wire [31:0]   trx_timeout_cycles,

    // ── Transceive response ──
    output reg           trx_done,
    output reg           trx_ok,
    output reg  [4:0]    trx_rx_len,          // 0..31 → 1..32 bytes
    output reg  [255:0]  trx_rx_data,         // byte0 at [255:248]
    output reg  [2:0]    trx_rx_last_bits,
    output reg  [7:0]    trx_error,

    // ── mfrc_reg_if request/response interface (to arbiter/shared reg_if) ──
    output reg           reg_req_valid,
    input  wire          reg_req_ready,
    output reg           reg_req_write,
    output reg  [5:0]    reg_req_addr,
    output reg  [4:0]    reg_req_len,
    output reg  [255:0]  reg_req_wdata,

    input  wire          reg_resp_valid,
    input  wire [255:0]  reg_resp_rdata,
    input  wire          reg_resp_ok
);

    // =====================================================================
    // MFRC522 register addresses (6-bit)
    // =====================================================================
    localparam [5:0] REG_COMMAND       = 6'h01;
    localparam [5:0] REG_COM_IRQ       = 6'h04;
    localparam [5:0] REG_ERROR         = 6'h06;
    localparam [5:0] REG_FIFO_DATA     = 6'h09;
    localparam [5:0] REG_FIFO_LEVEL    = 6'h0A;
    localparam [5:0] REG_CONTROL       = 6'h0C;
    localparam [5:0] REG_BIT_FRAMING   = 6'h0D;

    // =====================================================================
    // MFRC522 constants
    // =====================================================================
    localparam [7:0] CMD_TRANSCEIVE = 8'h0C;
    localparam [7:0] CMD_IDLE       = 8'h00;   // Idle command (cancel Transceive)
    localparam [7:0] FIFO_FLUSH     = 8'h80;   // FIFOLevelReg[7]
    localparam [7:0] START_SEND     = 8'h80;   // BitFramingReg[7]
    localparam [7:0] IRQ_RX         = 8'h20;   // ComIrqReg bit5
    localparam [7:0] IRQ_TIMER      = 8'h01;   // ComIrqReg bit0

    // reg_resp_ok is currently not used in this FSM; the higher layer can
    // optionally incorporate it into trx_ok/trx_error handling.

    // =====================================================================
    // Transceive FSM
    // =====================================================================
    //
    // The FSM uses a two-level structure:
    //   - A "step" register selects what register operation to perform.
    //   - A shared S_REG_ISSUE / S_REG_WAIT state pair handles the
    //     reg_req handshake, then jumps to a per-step return state.
    //
    // This eliminates the repeated "issued" flag pattern.

    localparam [3:0]
        S_IDLE        = 4'd0,
        S_SETUP       = 4'd1,   // load reg_req_* based on current step
        S_REG_ISSUE   = 4'd2,   // assert reg_req_valid when ready
        S_REG_WAIT    = 4'd3,   // wait for reg_resp_valid
        S_POLL        = 4'd4,   // poll ComIrqReg (issue + evaluate inline)
        S_CAPTURE     = 4'd5,   // capture read-response, advance step
        S_FINISH      = 4'd6;

    // Steps driven by the step register
    localparam [3:0]
        STEP_FLUSH      = 4'd0,
        STEP_BITFRAME   = 4'd1,
        STEP_FIFO_WR    = 4'd2,
        STEP_CMD        = 4'd3,
        STEP_START_SEND = 4'd4,
        STEP_POLL       = 4'd5,
        STEP_IDLE_CMD   = 4'd6,  // write CommandReg=Idle after poll
        STEP_RD_LEVEL   = 4'd7,
        STEP_RD_FIFO    = 4'd8,
        STEP_RD_CTRL    = 4'd9,
        STEP_RD_ERR     = 4'd10;

    reg [3:0]   state;
    reg [3:0]   step;
    reg [31:0]  timeout_cnt;
    reg         poll_success;
    reg         poll_outstanding;  // prevents issuing multiple ComIrqReg reads
    reg [5:0]   fifo_level;        // clamped byte count (0..32)

    // Latched request
    reg [4:0]   lat_tx_len;
    reg [255:0] lat_tx_data;
    reg [2:0]   lat_tx_last_bits;
    reg [31:0]  lat_timeout;

    assign trx_ready = (state == S_IDLE);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= S_IDLE;
            step             <= STEP_FLUSH;
            reg_req_valid    <= 1'b0;
            reg_req_write    <= 1'b0;
            reg_req_addr     <= 6'd0;
            reg_req_len      <= 5'd0;
            reg_req_wdata    <= 256'd0;
            trx_done         <= 1'b0;
            trx_ok           <= 1'b0;
            trx_rx_len       <= 5'd0;
            trx_rx_data      <= 256'd0;
            trx_rx_last_bits <= 3'd0;
            trx_error        <= 8'd0;
            timeout_cnt      <= 32'd0;
            poll_success     <= 1'b0;
            poll_outstanding <= 1'b0;
            fifo_level       <= 6'd0;
            lat_tx_len       <= 5'd0;
            lat_tx_data      <= 256'd0;
            lat_tx_last_bits <= 3'd0;
            lat_timeout      <= 32'd0;
        end else begin
            // Defaults
            reg_req_valid <= 1'b0;
            trx_done      <= 1'b0;

            case (state)

                // ─── IDLE ───────────────────────────────────────────
                S_IDLE: begin
                    if (trx_valid) begin
                        lat_tx_len       <= trx_tx_len;
                        lat_tx_data      <= trx_tx_data;
                        lat_tx_last_bits <= trx_tx_last_bits;
                        lat_timeout      <= trx_timeout_cycles;
                        timeout_cnt      <= 32'd0;
                        poll_success     <= 1'b0;
                        poll_outstanding <= 1'b0;
                        fifo_level       <= 6'd0;
                        step             <= STEP_FLUSH;
                        state            <= S_SETUP;
                    end
                end

                // ─── SETUP: load reg_req_* based on step ────────────
                S_SETUP: begin
                    case (step)
                        STEP_FLUSH: begin
                            reg_req_write <= 1'b1;
                            reg_req_addr  <= REG_FIFO_LEVEL;
                            reg_req_len   <= 5'd0;
                            reg_req_wdata <= {FIFO_FLUSH, 248'd0};
                        end
                        STEP_BITFRAME: begin
                            reg_req_write <= 1'b1;
                            reg_req_addr  <= REG_BIT_FRAMING;
                            reg_req_len   <= 5'd0;
                            reg_req_wdata <= {{5'b0, lat_tx_last_bits}, 248'd0};
                        end
                        STEP_FIFO_WR: begin
                            reg_req_write <= 1'b1;
                            reg_req_addr  <= REG_FIFO_DATA;
                            reg_req_len   <= lat_tx_len;
                            reg_req_wdata <= lat_tx_data;
                        end
                        STEP_CMD: begin
                            reg_req_write <= 1'b1;
                            reg_req_addr  <= REG_COMMAND;
                            reg_req_len   <= 5'd0;
                            reg_req_wdata <= {CMD_TRANSCEIVE, 248'd0};
                        end
                        STEP_START_SEND: begin
                            reg_req_write <= 1'b1;
                            reg_req_addr  <= REG_BIT_FRAMING;
                            reg_req_len   <= 5'd0;
                            reg_req_wdata <= {{1'b1, 4'b0, lat_tx_last_bits}, 248'd0};
                        end
                        STEP_IDLE_CMD: begin
                            reg_req_write <= 1'b1;
                            reg_req_addr  <= REG_COMMAND;
                            reg_req_len   <= 5'd0;
                            reg_req_wdata <= {CMD_IDLE, 248'd0};
                        end
                        STEP_RD_LEVEL: begin
                            reg_req_write <= 1'b0;
                            reg_req_addr  <= REG_FIFO_LEVEL;
                            reg_req_len   <= 5'd0;
                            reg_req_wdata <= 256'd0;
                        end
                        STEP_RD_FIFO: begin
                            // Skip FIFO read if empty (fifo_level==0 means
                            // FIFOLevelReg was 0); jump straight to RD_CTRL.
                            if (fifo_level == 6'd0) begin
                                trx_rx_len  <= 5'd0;
                                trx_rx_data <= 256'd0;
                                step        <= STEP_RD_CTRL;
                                // stay in S_SETUP to load next step
                            end else begin
                                reg_req_write <= 1'b0;
                                reg_req_addr  <= REG_FIFO_DATA;
                                // fifo_level is clamped to 1..32 here
                                reg_req_len   <= (fifo_level - 6'd1); // encode: 0 = 1 byte
                                reg_req_wdata <= 256'd0;
                            end
                        end
                        STEP_RD_CTRL: begin
                            reg_req_write <= 1'b0;
                            reg_req_addr  <= REG_CONTROL;
                            reg_req_len   <= 5'd0;
                            reg_req_wdata <= 256'd0;
                        end
                        STEP_RD_ERR: begin
                            reg_req_write <= 1'b0;
                            reg_req_addr  <= REG_ERROR;
                            reg_req_len   <= 5'd0;
                            reg_req_wdata <= 256'd0;
                        end
                        default: ;
                    endcase

                    // Poll is handled by its own state; others use the
                    // shared issue/wait pair.
                    if (step == STEP_POLL)
                        state <= S_POLL;
                    else if (step != STEP_RD_FIFO || fifo_level != 6'd0)
                        state <= S_REG_ISSUE;
                    // else: fifo_level==0 skip case stays in S_SETUP
                    // with step already advanced to STEP_RD_CTRL
                end

                // ─── REG_ISSUE: assert reg_req_valid ────────────────
                S_REG_ISSUE: begin
                    if (reg_req_ready) begin
                        reg_req_valid <= 1'b1;
                        state         <= S_REG_WAIT;
                    end
                end

                // ─── REG_WAIT: wait for response, then advance ──────
                S_REG_WAIT: begin
                    if (reg_resp_valid) begin
                        case (step)
                            // Write steps: just advance to next step
                            STEP_FLUSH:      begin step <= STEP_BITFRAME;   state <= S_SETUP; end
                            STEP_BITFRAME:   begin step <= STEP_FIFO_WR;    state <= S_SETUP; end
                            STEP_FIFO_WR:    begin step <= STEP_CMD;        state <= S_SETUP; end
                            STEP_CMD:        begin step <= STEP_START_SEND; state <= S_SETUP; end
                            STEP_START_SEND: begin step <= STEP_POLL;       state <= S_SETUP; end
                            STEP_IDLE_CMD: begin
                                // After clearing CommandReg, branch based on poll result
                                if (poll_success)
                                    step <= STEP_RD_LEVEL;
                                else
                                    step <= STEP_RD_ERR;
                                state <= S_SETUP;
                            end

                            // Read steps: go to CAPTURE to latch data
                            STEP_RD_LEVEL,
                            STEP_RD_FIFO,
                            STEP_RD_CTRL,
                            STEP_RD_ERR:     state <= S_CAPTURE;

                            default:         state <= S_IDLE;
                        endcase
                    end
                end

                // ─── POLL: read ComIrqReg, evaluate inline ──────────
                // timeout_cnt counts the number of poll round-trips,
                // not wall-clock cycles (see module header).
                S_POLL: begin
                    if (!poll_outstanding && !reg_req_valid && reg_req_ready) begin
                        // Issue the read
                        reg_req_valid    <= 1'b1;
                        reg_req_write    <= 1'b0;
                        reg_req_addr     <= REG_COM_IRQ;
                        reg_req_len      <= 5'd0;
                        reg_req_wdata    <= 256'd0;
                        poll_outstanding <= 1'b1;
                    end
                    if (reg_resp_valid) begin
                        poll_outstanding <= 1'b0;
                        timeout_cnt <= timeout_cnt + 1;
                        if (reg_resp_rdata[255:248] & IRQ_RX) begin
                            // RxIRq — success; clear CommandReg before reading FIFO
                            poll_success <= 1'b1;
                            step         <= STEP_IDLE_CMD;
                            state        <= S_SETUP;
                        end else if ((reg_resp_rdata[255:248] & IRQ_TIMER) ||
                                     (timeout_cnt >= lat_timeout)) begin
                            // TimerIRq or SW timeout — fail; clear CommandReg before reading ErrorReg
                            poll_success     <= 1'b0;
                            trx_rx_len       <= 5'd0;
                            trx_rx_data      <= 256'd0;
                            trx_rx_last_bits <= 3'd0;
                            step             <= STEP_IDLE_CMD;
                            state            <= S_SETUP;
                        end else begin
                            // No relevant IRQ yet — poll again
                            state <= S_POLL;
                        end
                    end
                end

                // ─── CAPTURE: latch read results, advance step ──────
                S_CAPTURE: begin
                    case (step)
                        STEP_RD_LEVEL: begin
                            // FIFOLevelReg: bit7=FlushBuffer, bits[6:0]=level (0..64)
                            // Clamp to 32 because our datapath supports max 32 bytes.
                            // Extract level from bits[6:0] => reg_resp_rdata[254:248]
                            if (reg_resp_rdata[254:248] > 7'd32)
                                fifo_level <= 6'd32;
                            else
                                fifo_level <= reg_resp_rdata[253:248];

                            step  <= STEP_RD_FIFO;
                            state <= S_SETUP;
                        end

                        STEP_RD_FIFO: begin
                            // fifo_level is 1..32 here. Encode: 0=1 byte
                            trx_rx_len  <= (fifo_level == 6'd0) ? 5'd0 : (fifo_level - 6'd1);
                            trx_rx_data <= reg_resp_rdata;
                            step        <= STEP_RD_CTRL;
                            state       <= S_SETUP;
                        end

                        STEP_RD_CTRL: begin
                            trx_rx_last_bits <= reg_resp_rdata[250:248];
                            step             <= STEP_RD_ERR;
                            state            <= S_SETUP;
                        end

                        STEP_RD_ERR: begin
                            trx_error <= reg_resp_rdata[255:248];
                            trx_ok    <= poll_success && (reg_resp_rdata[255:248] == 8'd0);
                            state     <= S_FINISH;
                        end

                        default: state <= S_IDLE;
                    endcase
                end

                // ─── FINISH: pulse trx_done, return to IDLE ─────────
                S_FINISH: begin
                    trx_done <= 1'b1;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
