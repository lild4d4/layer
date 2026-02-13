// nfc_spi.sv
// Controller for MFRC522 NFC reader via the PULP axi_spi_master.
//
// MFRC522 SPI protocol (single byte register access):
//   Write: send 1-byte addr {0, addr[5:0], 0}, then 1-byte data  → 16 bits TX, 0 bits RX
//   Read:  send 1-byte addr {1, addr[5:0], 0}, then read 1-byte  → 8 bits TX, 8 bits RX
//
// This module exposes a simple cmd interface to other on-chip logic and
// drives an axi_lite_master to program the PULP SPI master registers.

// Register offsets (byte addresses) of the PULP axi_spi_master
// The PULP AXI IF decodes register index as addr[5:1], so each
// register is at a 2-byte offset (not 4-byte).
`ifndef SPI_REG_DEFINES
`define SPI_REG_DEFINES
`define SPI_REG_STATUS 32'h0000_0000
`define SPI_REG_CLKDIV 32'h0000_0002
`define SPI_REG_SPICMD 32'h0000_0004
`define SPI_REG_SPIADR 32'h0000_0006
`define SPI_REG_SPILEN 32'h0000_0008
`define SPI_REG_SPIDUM 32'h0000_000A
`define SPI_REG_TXFIFO 32'h0000_0010
`define SPI_REG_RXFIFO 32'h0000_0020
`endif

module nfc_spi (
    input  wire        clk,
    input  wire        rst_n,

    // ── Simple command interface (directly from other modules) ───
    input  wire        cmd_valid,   // Pulse: start a transaction
    input  wire        cmd_write,   // 1 = write register, 0 = read register
    input  wire  [5:0] cmd_addr,    // MFRC522 register address (6 bits)
    input  wire  [7:0] cmd_wdata,   // Write data (ignored on read)
    output reg   [7:0] cmd_rdata,   // Read data (valid when cmd_done pulses)
    output reg         cmd_done,    // Pulse: transaction complete
    output wire        cmd_busy,    // High while a transaction is in progress

    // ── Interface to shared axi_lite_master (directly from other modules) ──
    output reg  [31:0] axi_req_addr,
    output reg  [31:0] axi_req_wdata,
    output reg         axi_req_write,
    output reg         axi_req_valid,
    input  wire [31:0] axi_resp_rdata,
    input  wire        axi_resp_done,
    input  wire        axi_busy
);

    // ── FSM states ──────────────────────────────────────────────
    // To perform one MFRC522 register read/write we must program
    // several PULP SPI master registers in sequence, then trigger.
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_SET_CMD    = 4'd1,   // Write SPI command register (the address byte)
        S_WAIT_CMD   = 4'd2,
        S_SET_LEN    = 4'd3,   // Write SPI length register
        S_WAIT_LEN   = 4'd4,
        S_SET_TXDATA = 4'd5,   // Write TX FIFO (write-data byte, only for writes)
        S_WAIT_TXDAT = 4'd6,
        S_TRIGGER    = 4'd7,   // Write STATUS register to start SPI xfer
        S_WAIT_TRIG  = 4'd8,
        S_POLL_STAT  = 4'd9,   // Read STATUS register until SPI is idle
        S_WAIT_POLL  = 4'd10,
        S_READ_RX    = 4'd11,  // Read RX FIFO (only for reads)
        S_WAIT_RX    = 4'd12,
        S_DONE       = 4'd13;

    reg [3:0] state;

    // Latched command
    reg        lat_write;
    reg  [5:0] lat_addr;
    reg  [7:0] lat_wdata;

    assign cmd_busy = (state != S_IDLE);

    // Helper: MFRC522 address byte
    // Bit 7: 1=read, 0=write.  Bits [6:1] = register address.  Bit 0 = 0.
    wire [7:0] mfrc_addr_byte = {~lat_write, lat_addr, 1'b0};

    // ── AXI request helper task (active for one clock) ──────────
    // We set axi_req_valid=1 for one cycle, then wait for axi_resp_done.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            lat_write      <= 1'b0;
            lat_addr       <= 6'h0;
            lat_wdata      <= 8'h0;
            cmd_done       <= 1'b0;
            cmd_rdata      <= 8'h0;
            axi_req_addr   <= 32'h0;
            axi_req_wdata  <= 32'h0;
            axi_req_write  <= 1'b0;
            axi_req_valid  <= 1'b0;
        end else begin
            cmd_done      <= 1'b0;
            axi_req_valid <= 1'b0;   // default: no request

            case (state)

                // ─────────────────────────────────────────────
                S_IDLE: begin
                    if (cmd_valid && !cmd_busy) begin
                        lat_write <= cmd_write;
                        lat_addr  <= cmd_addr;
                        lat_wdata <= cmd_wdata;
                        state     <= S_SET_CMD;
                    end
                end

                // ── Step 1: Write the SPI command register ───
                // The MFRC522 address byte goes into spi_cmd.
                // It is shifted out MSB-first as the "command phase".
                S_SET_CMD: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_SPICMD;
                        axi_req_wdata <= {mfrc_addr_byte, 24'h0}; // MSB-aligned in 32-bit word
                        axi_req_write <= 1'b1;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_CMD;
                    end
                end

                S_WAIT_CMD: begin
                    if (axi_resp_done)
                        state <= S_SET_LEN;
                end

                // ── Step 2: Write the SPI length register ────
                // cmd_len = 8 (1 byte command/address).
                // For write: data_len = 8 (1 byte TX data), no RX.
                // For read:  data_len = 8 (1 byte RX data), no TX data phase.
                S_SET_LEN: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_SPILEN;
                        // [7:0]   = cmd_len  = 8
                        // [15:8]  = addr_len = 0 (we don't use the addr phase)
                        // [31:16] = data_len = 8 bits
                        axi_req_wdata <= {16'd8, 8'd0, 8'd8};
                        axi_req_write <= 1'b1;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_LEN;
                    end
                end

                S_WAIT_LEN: begin
                    if (axi_resp_done)
                        state <= lat_write ? S_SET_TXDATA : S_TRIGGER;
                end

                // ── Step 3 (write only): Push TX data into FIFO ──
                S_SET_TXDATA: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_TXFIFO;
                        axi_req_wdata <= {lat_wdata, 24'h0}; // MSB-aligned
                        axi_req_write <= 1'b1;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_TXDAT;
                    end
                end

                S_WAIT_TXDAT: begin
                    if (axi_resp_done)
                        state <= S_TRIGGER;
                end

                // ── Step 4: Trigger the SPI transaction ──────
                // STATUS register:
                //   [0] = spi_rd,  [1] = spi_wr
                //   [11:8] = csreg → use CS1 for NFC (bit 1 = 1 → csreg = 4'b0010)
                S_TRIGGER: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_STATUS;
                        if (lat_write)
                            axi_req_wdata <= {20'h0, 4'b0010, 6'h0, 1'b1, 1'b0}; // wr=1, csreg=CS1
                        else
                            axi_req_wdata <= {20'h0, 4'b0010, 7'h0, 1'b1};        // rd=1, csreg=CS1
                        axi_req_write <= 1'b1;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_TRIG;
                    end
                end

                S_WAIT_TRIG: begin
                    if (axi_resp_done)
                        state <= S_POLL_STAT;
                end

                // ── Step 5: Poll STATUS until SPI master goes idle ──
                // Bit [0] of spi_ctrl_status = IDLE state (1 when idle)
                S_POLL_STAT: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_STATUS;
                        axi_req_write <= 1'b0;  // READ
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_POLL;
                    end
                end

                S_WAIT_POLL: begin
                    if (axi_resp_done) begin
                        // spi_ctrl_status[0] = 1 means IDLE
                        if (axi_resp_rdata[0])
                            state <= lat_write ? S_DONE : S_READ_RX;
                        else
                            state <= S_POLL_STAT; // keep polling
                    end
                end

                // ── Step 6 (read only): Read RX FIFO ─────────
                S_READ_RX: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_RXFIFO;
                        axi_req_write <= 1'b0;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_RX;
                    end
                end

                S_WAIT_RX: begin
                    if (axi_resp_done) begin
                        cmd_rdata <= axi_resp_rdata[7:0];
                        state     <= S_DONE;
                    end
                end

                // ── Done ─────────────────────────────────────
                S_DONE: begin
                    cmd_done <= 1'b1;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
