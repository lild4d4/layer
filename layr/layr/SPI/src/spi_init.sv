// spi_top.sv
// Top-level SPI subsystem.
//
// Integrates:
//   - eeprom_spi   : simple cmd interface for EEPROM (CS0)
//   - nfc_spi      : simple cmd interface for MFRC522 NFC (CS1)
//   - Arbiter with grant tracking: serialises access to the shared AXI bus
//   - axi_lite_master : translates simple req/resp into AXI4 transactions
//   - axi_spi_master  : PULP register-mapped SPI master (AXI4 slave)
//   - Clock divider init FSM: configures SPI clock after reset
//
// Other modules on the chip talk ONLY to the eeprom_* / nfc_* cmd ports.

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

module spi_top #(
    parameter AXI4_ADDRESS_WIDTH = 32,
    parameter AXI4_DATA_WIDTH    = 32,
    parameter AXI4_ID_WIDTH      = 16,
    parameter AXI4_USER_WIDTH    = 4,
    parameter SPI_BUFFER_DEPTH   = 8,
    parameter [7:0] SPI_CLK_DIV  = 8'd24  // Default: sys_clk / (2*(24+1)) ≈ 1 MHz @ 50 MHz
)(
    input  wire        clk,
    input  wire        rst_n,

    // ── EEPROM simple command interface (for other modules) ──────
    input  wire        eeprom_cmd_valid,
    input  wire        eeprom_cmd_write,
    input  wire  [6:0] eeprom_cmd_addr,
    input  wire  [7:0] eeprom_cmd_wdata,
    output wire  [7:0] eeprom_cmd_rdata,
    output wire        eeprom_cmd_done,
    output wire        eeprom_cmd_busy,

    // ── NFC simple command interface (for other modules) ─────────
    input  wire        nfc_cmd_valid,
    input  wire        nfc_cmd_write,
    input  wire  [5:0] nfc_cmd_addr,
    input  wire  [7:0] nfc_cmd_wdata,
    output wire  [7:0] nfc_cmd_rdata,
    output wire        nfc_cmd_done,
    output wire        nfc_cmd_busy,

    // ── SPI physical pins ────────────────────────────────────────
    output wire        spi_clk,
    output wire        spi_csn0,       // EEPROM chip select (active low)
    output wire        spi_csn1,       // NFC chip select (active low)
    output wire        spi_csn2,
    output wire        spi_csn3,
    output wire  [1:0] spi_mode,
    output wire        spi_sdo0,
    output wire        spi_sdo1,
    output wire        spi_sdo2,
    output wire        spi_sdo3,
    input  wire        spi_sdi0,
    input  wire        spi_sdi1,
    input  wire        spi_sdi2,
    input  wire        spi_sdi3
);

    // ================================================================
    // Internal wires
    // ================================================================

    // EEPROM controller ↔ arbiter
    wire [31:0] eeprom_axi_req_addr;
    wire [31:0] eeprom_axi_req_wdata;
    wire        eeprom_axi_req_write;
    wire        eeprom_axi_req_valid;
    wire        eeprom_axi_resp_done;   // per-controller done
    wire        eeprom_axi_busy;        // per-controller busy

    // NFC controller ↔ arbiter
    wire [31:0] nfc_axi_req_addr;
    wire [31:0] nfc_axi_req_wdata;
    wire        nfc_axi_req_write;
    wire        nfc_axi_req_valid;
    wire        nfc_axi_resp_done;      // per-controller done
    wire        nfc_axi_busy;           // per-controller busy

    // Init FSM ↔ arbiter
    reg  [31:0] init_axi_req_addr;
    reg  [31:0] init_axi_req_wdata;
    reg         init_axi_req_write;
    reg         init_axi_req_valid;
    wire        init_axi_resp_done;
    wire        init_axi_busy;

    // Arbiter ↔ axi_lite_master
    reg  [31:0] arb_req_addr;
    reg  [31:0] arb_req_wdata;
    reg         arb_req_write;
    reg         arb_req_valid;
    wire [31:0] arb_resp_rdata;
    wire        arb_resp_done;
    wire        arb_resp_error;
    wire        arb_busy;

    // Grant tracking: who owns the current AXI transaction?
    // 0 = init, 1 = eeprom, 2 = nfc
    reg [1:0] grant;
    reg [1:0] grant_locked;
    reg       grant_active;  // A transaction is in-flight

    // axi_lite_master ↔ axi_spi_master (AXI4 bus)
    wire [AXI4_ADDRESS_WIDTH-1:0] axi_awaddr;
    wire [AXI4_ID_WIDTH-1:0]      axi_awid;
    wire [7:0]                    axi_awlen;
    wire [AXI4_USER_WIDTH-1:0]    axi_awuser;
    wire                          axi_awvalid;
    wire                          axi_awready;

    wire [AXI4_DATA_WIDTH-1:0]    axi_wdata;
    wire [AXI4_DATA_WIDTH/8-1:0]  axi_wstrb;
    wire                          axi_wlast;
    wire [AXI4_USER_WIDTH-1:0]    axi_wuser;
    wire                          axi_wvalid;
    wire                          axi_wready;

    wire [AXI4_ID_WIDTH-1:0]      axi_bid;
    wire [1:0]                    axi_bresp;
    wire                          axi_bvalid;
    wire                          axi_bready;

    wire [AXI4_ADDRESS_WIDTH-1:0] axi_araddr;
    wire [AXI4_ID_WIDTH-1:0]      axi_arid;
    wire [7:0]                    axi_arlen;
    wire [AXI4_USER_WIDTH-1:0]    axi_aruser;
    wire                          axi_arvalid;
    wire                          axi_arready;

    wire [AXI4_DATA_WIDTH-1:0]    axi_rdata;
    wire [1:0]                    axi_rresp;
    wire                          axi_rlast;
    wire                          axi_rvalid;
    wire                          axi_rready;

    wire [AXI4_ID_WIDTH-1:0]      axi_rid;
    wire [AXI4_USER_WIDTH-1:0]    axi_ruser;

    wire [1:0] spi_events;

    // ================================================================
    // SPI clock divider init FSM
    // ================================================================
    // After reset, we must write REG_CLKDIV before any SPI transaction.
    reg        init_done;

    localparam INIT_IDLE     = 2'd0;
    localparam INIT_WRITE    = 2'd1;
    localparam INIT_WAIT     = 2'd2;
    localparam INIT_COMPLETE = 2'd3;
    reg [1:0] init_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_state       <= INIT_IDLE;
            init_done        <= 1'b0;
            init_axi_req_addr  <= 32'h0;
            init_axi_req_wdata <= 32'h0;
            init_axi_req_write <= 1'b0;
            init_axi_req_valid <= 1'b0;
        end else begin
            init_axi_req_valid <= 1'b0;

            case (init_state)
                INIT_IDLE: begin
                    init_state <= INIT_WRITE;
                end

                INIT_WRITE: begin
                    if (!arb_busy) begin
                        init_axi_req_addr  <= `SPI_REG_CLKDIV;
                        init_axi_req_wdata <= {24'h0, SPI_CLK_DIV};
                        init_axi_req_write <= 1'b1;
                        init_axi_req_valid <= 1'b1;
                        init_state         <= INIT_WAIT;
                    end
                end

                INIT_WAIT: begin
                    if (init_axi_resp_done) begin
                        init_done  <= 1'b1;
                        init_state <= INIT_COMPLETE;
                    end
                end

                INIT_COMPLETE: begin
                    // Stay here forever — init only runs once
                end
            endcase
        end
    end

    // ================================================================
    // EEPROM controller
    // ================================================================
    eeprom_spi u_eeprom (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_valid      (eeprom_cmd_valid & init_done),  // Block until init done
        .cmd_write      (eeprom_cmd_write),
        .cmd_addr       (eeprom_cmd_addr),
        .cmd_wdata      (eeprom_cmd_wdata),
        .cmd_rdata      (eeprom_cmd_rdata),
        .cmd_done       (eeprom_cmd_done),
        .cmd_busy       (eeprom_cmd_busy),
        .axi_req_addr   (eeprom_axi_req_addr),
        .axi_req_wdata  (eeprom_axi_req_wdata),
        .axi_req_write  (eeprom_axi_req_write),
        .axi_req_valid  (eeprom_axi_req_valid),
        .axi_resp_rdata (arb_resp_rdata),
        .axi_resp_done  (eeprom_axi_resp_done),
        .axi_busy       (eeprom_axi_busy)
    );

    // ================================================================
    // NFC controller
    // ================================================================
    nfc_spi u_nfc (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_valid      (nfc_cmd_valid & init_done),  // Block until init done
        .cmd_write      (nfc_cmd_write),
        .cmd_addr       (nfc_cmd_addr),
        .cmd_wdata      (nfc_cmd_wdata),
        .cmd_rdata      (nfc_cmd_rdata),
        .cmd_done       (nfc_cmd_done),
        .cmd_busy       (nfc_cmd_busy),
        .axi_req_addr   (nfc_axi_req_addr),
        .axi_req_wdata  (nfc_axi_req_wdata),
        .axi_req_write  (nfc_axi_req_write),
        .axi_req_valid  (nfc_axi_req_valid),
        .axi_resp_rdata (arb_resp_rdata),
        .axi_resp_done  (nfc_axi_resp_done),
        .axi_busy       (nfc_axi_busy)
    );

    // ================================================================
    // Arbiter with grant tracking
    // ================================================================
    // When a request is accepted (valid & !busy), we lock the grant
    // until arb_resp_done. This ensures the response is routed back
    // to the correct requester only.
    //
    // Priority: init > eeprom > nfc (init only runs once at startup)

    // Route resp_done and busy only to the granted controller
    assign init_axi_resp_done   = arb_resp_done & grant_active & (grant_locked == 2'd0);
    assign eeprom_axi_resp_done = arb_resp_done & grant_active & (grant_locked == 2'd1);
    assign nfc_axi_resp_done    = arb_resp_done & grant_active & (grant_locked == 2'd2);

    // A controller sees "busy" if the bus is busy OR another controller owns it
    assign init_axi_busy   = arb_busy | (grant_active & (grant_locked != 2'd0));
    assign eeprom_axi_busy = arb_busy | (grant_active & (grant_locked != 2'd1));
    assign nfc_axi_busy    = arb_busy | (grant_active & (grant_locked != 2'd2));

    // Determine which requester to grant (combinational)
    always @(*) begin
        arb_req_addr  = 32'h0;
        arb_req_wdata = 32'h0;
        arb_req_write = 1'b0;
        arb_req_valid = 1'b0;
        grant         = 2'd0;

        if (!grant_active || arb_resp_done) begin
            // Bus is free (or freeing this cycle), accept a new request
            if (init_axi_req_valid && !init_done) begin
                arb_req_addr  = init_axi_req_addr;
                arb_req_wdata = init_axi_req_wdata;
                arb_req_write = init_axi_req_write;
                arb_req_valid = 1'b1;
                grant         = 2'd0;
            end else if (eeprom_axi_req_valid) begin
                arb_req_addr  = eeprom_axi_req_addr;
                arb_req_wdata = eeprom_axi_req_wdata;
                arb_req_write = eeprom_axi_req_write;
                arb_req_valid = 1'b1;
                grant         = 2'd1;
            end else if (nfc_axi_req_valid) begin
                arb_req_addr  = nfc_axi_req_addr;
                arb_req_wdata = nfc_axi_req_wdata;
                arb_req_write = nfc_axi_req_write;
                arb_req_valid = 1'b1;
                grant         = 2'd2;
            end
        end
    end

    // Lock the grant while a transaction is in-flight
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grant_locked <= 2'd0;
            grant_active <= 1'b0;
        end else begin
            if (arb_resp_done) begin
                // Transaction complete — release lock
                grant_active <= 1'b0;
            end
            if (arb_req_valid && !arb_busy) begin
                // New request accepted — lock grant
                grant_locked <= grant;
                grant_active <= 1'b1;
            end
        end
    end

    // ================================================================
    // AXI Lite Master (simple req/resp → AXI4)
    // ================================================================
    axi_lite_master #(
        .AXI4_ADDRESS_WIDTH (AXI4_ADDRESS_WIDTH),
        .AXI4_DATA_WIDTH    (AXI4_DATA_WIDTH),
        .AXI4_ID_WIDTH      (AXI4_ID_WIDTH),
        .AXI4_USER_WIDTH    (AXI4_USER_WIDTH)
    ) u_axi_master (
        .clk            (clk),
        .rst_n          (rst_n),

        .req_addr       (arb_req_addr),
        .req_wdata      (arb_req_wdata),
        .req_write      (arb_req_write),
        .req_valid      (arb_req_valid),
        .resp_rdata     (arb_resp_rdata),
        .resp_done      (arb_resp_done),
        .resp_error     (arb_resp_error),
        .busy           (arb_busy),

        .m_axi_awaddr   (axi_awaddr),
        .m_axi_awid     (axi_awid),
        .m_axi_awlen    (axi_awlen),
        .m_axi_awuser   (axi_awuser),
        .m_axi_awvalid  (axi_awvalid),
        .m_axi_awready  (axi_awready),

        .m_axi_wdata    (axi_wdata),
        .m_axi_wstrb    (axi_wstrb),
        .m_axi_wlast    (axi_wlast),
        .m_axi_wuser    (axi_wuser),
        .m_axi_wvalid   (axi_wvalid),
        .m_axi_wready   (axi_wready),

        .m_axi_bid      (axi_bid),
        .m_axi_bresp    (axi_bresp),
        .m_axi_bvalid   (axi_bvalid),
        .m_axi_bready   (axi_bready),

        .m_axi_araddr   (axi_araddr),
        .m_axi_arid     (axi_arid),
        .m_axi_arlen    (axi_arlen),
        .m_axi_aruser   (axi_aruser),
        .m_axi_arvalid  (axi_arvalid),
        .m_axi_arready  (axi_arready),

        .m_axi_rdata    (axi_rdata),
        .m_axi_rresp    (axi_rresp),
        .m_axi_rlast    (axi_rlast),
        .m_axi_rvalid   (axi_rvalid),
        .m_axi_rready   (axi_rready)
    );

    // ================================================================
    // PULP AXI SPI Master
    // ================================================================
    axi_spi_master #(
        .AXI4_ADDRESS_WIDTH (AXI4_ADDRESS_WIDTH),
        .AXI4_RDATA_WIDTH   (AXI4_DATA_WIDTH),
        .AXI4_WDATA_WIDTH   (AXI4_DATA_WIDTH),
        .AXI4_USER_WIDTH    (AXI4_USER_WIDTH),
        .AXI4_ID_WIDTH      (AXI4_ID_WIDTH),
        .BUFFER_DEPTH       (SPI_BUFFER_DEPTH)
    ) u_spi_master (
        .s_axi_aclk     (clk),
        .s_axi_aresetn  (rst_n),

        .s_axi_awvalid  (axi_awvalid),
        .s_axi_awid     (axi_awid),
        .s_axi_awlen    (axi_awlen),
        .s_axi_awaddr   (axi_awaddr),
        .s_axi_awuser   (axi_awuser),
        .s_axi_awready  (axi_awready),

        .s_axi_wvalid   (axi_wvalid),
        .s_axi_wdata    (axi_wdata),
        .s_axi_wstrb    (axi_wstrb),
        .s_axi_wlast    (axi_wlast),
        .s_axi_wuser    (axi_wuser),
        .s_axi_wready   (axi_wready),

        .s_axi_bvalid   (axi_bvalid),
        .s_axi_bid      (axi_bid),
        .s_axi_bresp    (axi_bresp),
        .s_axi_buser    (),
        .s_axi_bready   (axi_bready),

        .s_axi_arvalid  (axi_arvalid),
        .s_axi_arid     (axi_arid),
        .s_axi_arlen    (axi_arlen),
        .s_axi_araddr   (axi_araddr),
        .s_axi_aruser   (axi_aruser),
        .s_axi_arready  (axi_arready),

        .s_axi_rvalid   (axi_rvalid),
        .s_axi_rid      (axi_rid),
        .s_axi_rdata    (axi_rdata),
        .s_axi_rresp    (axi_rresp),
        .s_axi_rlast    (axi_rlast),
        .s_axi_ruser    (axi_ruser),
        .s_axi_rready   (axi_rready),

        .events_o       (spi_events),

        .spi_clk        (spi_clk),
        .spi_csn0       (spi_csn0),
        .spi_csn1       (spi_csn1),
        .spi_csn2       (spi_csn2),
        .spi_csn3       (spi_csn3),
        .spi_mode       (spi_mode),
        .spi_sdo0       (spi_sdo0),
        .spi_sdo1       (spi_sdo1),
        .spi_sdo2       (spi_sdo2),
        .spi_sdo3       (spi_sdo3),
        .spi_sdi0       (spi_sdi0),
        .spi_sdi1       (spi_sdi1),
        .spi_sdi2       (spi_sdi2),
        .spi_sdi3       (spi_sdi3)
    );

endmodule
