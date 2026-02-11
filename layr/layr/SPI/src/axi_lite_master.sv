// axi_lite_master.v
// Handles one AXI4 transaction at a time (write or read)
// Simple blocking interface for use with a controller FSM

module axi_lite_master #(
    parameter AXI4_ADDRESS_WIDTH = 32,
    parameter AXI4_DATA_WIDTH    = 32,
    parameter AXI4_ID_WIDTH      = 16,
    parameter AXI4_USER_WIDTH    = 4
)(
    input  wire clk,
    input  wire rst_n,

    // ── Simple interface your FSM talks to ──────────────────
    input  wire [AXI4_ADDRESS_WIDTH-1:0] req_addr,
    input  wire [AXI4_DATA_WIDTH-1:0]    req_wdata,
    input  wire                          req_write,  // 1=write, 0=read
    input  wire                          req_valid,  // pulse to start
    output reg  [AXI4_DATA_WIDTH-1:0]    resp_rdata,
    output reg                           resp_done,  // pulse when complete
    output reg                           resp_error, // pulse on AXI error
    output reg                           busy,

    // ── AXI4 Write Address Channel ──────────────────────────
    output reg  [AXI4_ADDRESS_WIDTH-1:0] m_axi_awaddr,
    output reg  [AXI4_ID_WIDTH-1:0]      m_axi_awid,
    output reg  [7:0]                    m_axi_awlen,
    output reg  [AXI4_USER_WIDTH-1:0]    m_axi_awuser,
    output reg                           m_axi_awvalid,
    input  wire                          m_axi_awready,

    // ── AXI4 Write Data Channel ─────────────────────────────
    output reg  [AXI4_DATA_WIDTH-1:0]    m_axi_wdata,
    output reg  [AXI4_DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output reg                           m_axi_wlast,
    output reg  [AXI4_USER_WIDTH-1:0]    m_axi_wuser,
    output reg                           m_axi_wvalid,
    input  wire                          m_axi_wready,

    // ── AXI4 Write Response Channel ─────────────────────────
    input  wire [AXI4_ID_WIDTH-1:0]      m_axi_bid,
    input  wire [1:0]                    m_axi_bresp,
    input  wire                          m_axi_bvalid,
    output reg                           m_axi_bready,

    // ── AXI4 Read Address Channel ───────────────────────────
    output reg  [AXI4_ADDRESS_WIDTH-1:0] m_axi_araddr,
    output reg  [AXI4_ID_WIDTH-1:0]      m_axi_arid,
    output reg  [7:0]                    m_axi_arlen,
    output reg  [AXI4_USER_WIDTH-1:0]    m_axi_aruser,
    output reg                           m_axi_arvalid,
    input  wire                          m_axi_arready,

    // ── AXI4 Read Data Channel ──────────────────────────────
    input  wire [AXI4_DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]                    m_axi_rresp,
    input  wire                          m_axi_rlast,
    input  wire                          m_axi_rvalid,
    output reg                           m_axi_rready
);

    // FSM states
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_WR_ADDR   = 3'd1,   // Drive write address + data channels
        S_WR_RESP   = 3'd2,   // Wait for write response (BVALID)
        S_RD_ADDR   = 3'd3,   // Drive read address channel
        S_RD_DATA   = 3'd4,   // Wait for read data (RVALID)
        S_DONE      = 3'd5;

    reg [2:0] state;

    // Latch request on entry
    reg [AXI4_ADDRESS_WIDTH-1:0] addr_latch;
    reg [AXI4_DATA_WIDTH-1:0]    wdata_latch;
    reg                          error_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            busy           <= 1'b0;
            resp_done      <= 1'b0;
            resp_error     <= 1'b0;
            error_latch    <= 1'b0;
            resp_rdata     <= 32'h0;

            m_axi_awvalid  <= 1'b0;
            m_axi_awaddr   <= 'h0;
            m_axi_awid     <= 'h0;
            m_axi_awlen    <= 8'h0;   // Single beat (len=0 means 1 transfer)
            m_axi_awuser   <= 'h0;

            m_axi_wvalid   <= 1'b0;
            m_axi_wdata    <= 32'h0;
            m_axi_wstrb    <= 4'hF;   // All byte lanes enabled
            m_axi_wlast    <= 1'b1;   // Always last for single beat
            m_axi_wuser    <= 'h0;

            m_axi_bready   <= 1'b0;

            m_axi_arvalid  <= 1'b0;
            m_axi_araddr   <= 'h0;
            m_axi_arid     <= 'h0;
            m_axi_arlen    <= 8'h0;
            m_axi_aruser   <= 'h0;

            m_axi_rready   <= 1'b0;
        end else begin
            // Default: pulses are single cycle
            resp_done  <= 1'b0;
            resp_error <= 1'b0;

            case (state)

                // ─────────────────────────────────────────────
                S_IDLE: begin
                    busy <= 1'b0;
                    if (req_valid) begin
                        addr_latch  <= req_addr;
                        wdata_latch <= req_wdata;
                        busy        <= 1'b1;
                        state       <= req_write ? S_WR_ADDR : S_RD_ADDR;
                    end
                end

                // ─────────────────────────────────────────────
                // WRITE: present address and data simultaneously
                // AXI allows AW and W channels to be presented
                // at the same time for single-beat transfers.
                //
                // Guard: only check ready after valid has been
                // registered high (m_axi_awvalid is the current
                // registered value; it is 0 on the first cycle
                // we enter this state).
                // ─────────────────────────────────────────────
                S_WR_ADDR: begin
                    m_axi_awvalid <= 1'b1;
                    m_axi_awaddr  <= addr_latch;
                    m_axi_wvalid  <= 1'b1;
                    m_axi_wdata   <= wdata_latch;
                    m_axi_wstrb   <= 4'hF;
                    m_axi_wlast   <= 1'b1;

                    // Both channels accepted?
                    if (m_axi_awvalid && m_axi_wvalid &&
                        m_axi_awready && m_axi_wready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b0;
                        m_axi_bready  <= 1'b1;  // Ready for response
                        state         <= S_WR_RESP;
                    // Address accepted but data not yet?
                    end else if (m_axi_awvalid && m_axi_awready && !m_axi_wready) begin
                        m_axi_awvalid <= 1'b0;
                        // Keep wvalid asserted until wready
                    // Data accepted but address not yet?
                    end else if (m_axi_wvalid && !m_axi_awready && m_axi_wready) begin
                        m_axi_wvalid  <= 1'b0;
                        // Keep awvalid asserted until awready
                    end
                    // If neither ready yet: stay here, both valid stay high
                end

                // ─────────────────────────────────────────────
                S_WR_RESP: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        error_latch  <= (m_axi_bresp != 2'b00);
                        state        <= S_DONE;
                    end
                end

                // ─────────────────────────────────────────────
                S_RD_ADDR: begin
                    m_axi_arvalid <= 1'b1;
                    m_axi_araddr  <= addr_latch;

                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;  // Ready to receive data
                        state         <= S_RD_DATA;
                    end
                end

                // ─────────────────────────────────────────────
                S_RD_DATA: begin
                    if (m_axi_rvalid) begin
                        resp_rdata   <= m_axi_rdata;
                        error_latch  <= (m_axi_rresp != 2'b00);
                        m_axi_rready <= 1'b0;
                        state        <= S_DONE;
                    end
                end

                // ─────────────────────────────────────────────
                S_DONE: begin
                    resp_done  <= 1'b1;
                    resp_error <= error_latch;
                    error_latch <= 1'b0;
                    busy       <= 1'b0;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
