// eeprom_ctrl.sv
// Controller for SPI EEPROM (e.g. 25LC/AT25) via the PULP axi_spi_master.

`ifndef SPI_REG_DEFINES
`define SPI_REG_DEFINES
`define SPI_REG_STATUS 32'h0000_0000
`define SPI_REG_CLKDIV 32'h0000_0004
`define SPI_REG_SPICMD 32'h0000_0008
`define SPI_REG_SPIADR 32'h0000_000C
`define SPI_REG_SPILEN 32'h0000_0010
`define SPI_REG_SPIDUM 32'h0000_0014
`define SPI_REG_TXFIFO 32'h0000_0020
`define SPI_REG_RXFIFO 32'h0000_0040
`endif

module eeprom_spi (
    input  wire        clk,
    input  wire        rst_n,

    // ── Simple command interface ────────────────────────────────
    input  wire        cmd_valid,   // Pulse: start a transaction
    input  wire        cmd_write,   // 1 = write byte, 0 = read byte
    input  wire  [6:0] cmd_addr,    // EEPROM byte address (7 bits → 128 bytes)
    input  wire  [7:0] cmd_wdata,   // Write data (ignored on read)
    output reg   [7:0] cmd_rdata,   // Read data (valid when cmd_done pulses)
    output reg         cmd_done,    // Pulse: transaction complete
    output wire        cmd_busy,    // High while a transaction is in progress

    // ── Interface to shared axi_lite_master ─────────────────────
    output reg  [31:0] axi_req_addr,
    output reg  [31:0] axi_req_wdata,
    output reg         axi_req_write,
    output reg         axi_req_valid,
    input  wire [31:0] axi_resp_rdata,
    input  wire        axi_resp_done,
    input  wire        axi_busy
);

    // ── FSM states ──────────────────────────────────────────────
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_SET_CMD    = 4'd1,   // Write SPI command register (opcode)
        S_WAIT_CMD   = 4'd2,
        S_SET_ADDR   = 4'd3,   // Write SPI address register
        S_WAIT_ADDR  = 4'd4,
        S_SET_LEN    = 4'd5,   // Write SPI length register
        S_WAIT_LEN   = 4'd6,
        S_SET_TXDATA = 4'd7,   // Write TX FIFO (only for writes)
        S_WAIT_TXDAT = 4'd8,
        S_TRIGGER    = 4'd9,   // Write STATUS to start SPI xfer
        S_WAIT_TRIG  = 4'd10,
        S_POLL_STAT  = 4'd11,  // Poll STATUS until idle
        S_WAIT_POLL  = 4'd12,
        S_READ_RX    = 4'd13,  // Read RX FIFO (only for reads)
        S_WAIT_RX    = 4'd14,
        S_DONE       = 4'd15;

    reg [3:0] state;

    // Latched command
    reg        lat_write;
    reg  [6:0] lat_addr;
    reg  [7:0] lat_wdata;

    assign cmd_busy = (state != S_IDLE);

    // EEPROM SPI opcodes
    localparam [7:0] OPCODE_READ  = 8'h03;
    localparam [7:0] OPCODE_WRITE = 8'h02;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            lat_write      <= 1'b0;
            lat_addr       <= 7'h0;
            lat_wdata      <= 8'h0;
            cmd_done       <= 1'b0;
            cmd_rdata      <= 8'h0;
            axi_req_addr   <= 32'h0;
            axi_req_wdata  <= 32'h0;
            axi_req_write  <= 1'b0;
            axi_req_valid  <= 1'b0;
        end else begin
            cmd_done      <= 1'b0;
            axi_req_valid <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (cmd_valid && !cmd_busy) begin
                        lat_write <= cmd_write;
                        lat_addr  <= cmd_addr;
                        lat_wdata <= cmd_wdata;
                        state     <= S_SET_CMD;
                    end
                end

                // ── Step 1: Write SPI command register (opcode) ──
                S_SET_CMD: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_SPICMD;
                        axi_req_wdata <= lat_write ?
                            {OPCODE_WRITE, 24'h0} :  // MSB-aligned
                            {OPCODE_READ,  24'h0};
                        axi_req_write <= 1'b1;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_CMD;
                    end
                end

                S_WAIT_CMD: begin
                    if (axi_resp_done)
                        state <= S_SET_ADDR;
                end

                // ── Step 2: Write SPI address register ───────────
                S_SET_ADDR: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_SPIADR;
                        // 7-bit address, MSB-aligned in 32-bit word
                        // The SPI master shifts addr_len bits from MSB
                        axi_req_wdata <= {1'b0, lat_addr, 24'h0};
                        axi_req_write <= 1'b1;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_ADDR;
                    end
                end

                S_WAIT_ADDR: begin
                    if (axi_resp_done)
                        state <= S_SET_LEN;
                end

                // ── Step 3: Write SPI length register ────────────
                S_SET_LEN: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_SPILEN;
                        // [7:0]   = cmd_len  = 8 (1 byte opcode)
                        // [15:8]  = addr_len = 8 (1 byte address)
                        // [31:16] = data_len = 8 (1 byte data)
                        axi_req_wdata <= {16'd8, 8'd8, 8'd8};
                        axi_req_write <= 1'b1;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_LEN;
                    end
                end

                S_WAIT_LEN: begin
                    if (axi_resp_done)
                        state <= lat_write ? S_SET_TXDATA : S_TRIGGER;
                end

                // ── Step 4 (write only): Push TX data into FIFO ──
                S_SET_TXDATA: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_TXFIFO;
                        axi_req_wdata <= {lat_wdata, 24'h0};
                        axi_req_write <= 1'b1;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_TXDAT;
                    end
                end

                S_WAIT_TXDAT: begin
                    if (axi_resp_done)
                        state <= S_TRIGGER;
                end

                // ── Step 5: Trigger the SPI transaction ──────────
                // STATUS[0]=rd, [1]=wr, [11:8]=csreg
                // CS0 for EEPROM → csreg = 4'b0001
                S_TRIGGER: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_STATUS;
                        if (lat_write)
                            axi_req_wdata <= {20'h0, 4'b0001, 6'h0, 1'b1, 1'b0}; // wr=1, csreg=CS0
                        else
                            axi_req_wdata <= {20'h0, 4'b0001, 7'h0, 1'b1};        // rd=1, csreg=CS0
                        axi_req_write <= 1'b1;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_TRIG;
                    end
                end

                S_WAIT_TRIG: begin
                    if (axi_resp_done)
                        state <= S_POLL_STAT;
                end

                // ── Step 6: Poll STATUS until SPI idle ───────────
                S_POLL_STAT: begin
                    if (!axi_busy) begin
                        axi_req_addr  <= `SPI_REG_STATUS;
                        axi_req_write <= 1'b0;
                        axi_req_valid <= 1'b1;
                        state         <= S_WAIT_POLL;
                    end
                end

                S_WAIT_POLL: begin
                    if (axi_resp_done) begin
                        if (axi_resp_rdata[0])
                            state <= lat_write ? S_DONE : S_READ_RX;
                        else
                            state <= S_POLL_STAT;
                    end
                end

                // ── Step 7 (read only): Read RX FIFO ─────────────
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

                S_DONE: begin
                    cmd_done <= 1'b1;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
