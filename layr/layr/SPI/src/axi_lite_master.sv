// =============================================================================
// spi_axi_lite_master.sv
//
// AXI-Lite master that bridges a simple req/resp interface to the PULP
// axi_spi_master register bank.
//
// Sequence of operations on each req_valid_i pulse:
//   1. (once after reset)  Write CLKDIV register to set ~4 MHz SPI clock.
//   2. Write SPILEN to configure data length.
//   3. For WRITE: push TX data into FIFO.
//   4. Write STATUS to select CS and trigger spi_rd or spi_wr.
//   5. Poll STATUS until bit[0] (IDLE) goes high → transfer complete.
//   6. For READ: read RX FIFO.
//   7. Pulse resp_done_o.
//
// Register map (from spi_master_axi_if.sv, 32-bit data bus):
//   3'b000  STATUS   – [0] idle, [1] wr, ... [11:8] csreg  (read: spi_status)
//   3'b001  CLKDIV   – [7:0] clock divider
//   3'b010  SPICMD   – [31:0] command
//   3'b011  SPIADR   – [31:0] SPI address
//   3'b100  SPILEN   – [5:0] cmd_len, [13:8] addr_len, [31:16] data_len
//   3'b101  SPIDUM   – [15:0] dummy_rd, [31:16] dummy_wr
//   TX FIFO write address: byte addr 0x20  (wr_addr[3]=1)
//   RX FIFO read  address: byte addr 0x40  (rd_addr[4]=1)
//
// AXI channel suffixes:
//   _AW = Address Write channel
//   _W  = Write Data channel
//   _B  = Write Response channel
//   _AR = Address Read channel
//   _R  = Read Data channel
// =============================================================================

module axi_lite_master #(
    parameter       AXI4_ADDRESS_WIDTH = 32,
    parameter       AXI4_DATA_WIDTH    = 32,
    parameter       AXI4_ID_WIDTH      = 16,
    parameter       AXI4_USER_WIDTH    = 4,
    // SPI clock divider: spi_clk = axi_clk / (2*(CLKDIV+1))
    // For 50 MHz AXI clock → CLKDIV=5 gives ~4.17 MHz
    parameter [7:0] SPI_CLKDIV         = 8'd5
) (
    input wire clk,
    input wire rst_n,

    // ---- Simple request / response interface ----
    input  wire [AXI4_ADDRESS_WIDTH-1:0] req_addr_i,    // SPI address for cmd
    input  wire [   AXI4_DATA_WIDTH-1:0] req_wdata_i,   // write data (32 bits)
    input  wire                          req_cs_i,      // 1=CS1 (nfc), 0=CS0 (eeprom)
    input  wire                          req_write_i,   // 1=write, 0=read
    input  wire                          req_valid_i,   // pulse to start
    output reg  [   AXI4_DATA_WIDTH-1:0] resp_rdata_o,
    output reg                           resp_done_o,   // pulse when complete
    output reg                           resp_error_o,  // pulse on AXI error
    output reg                           busy_o,

    // ---- AXI4 master interface (to axi_spi_master slave) ----
    output reg                           m_axi_awvalid,
    output reg  [     AXI4_ID_WIDTH-1:0] m_axi_awid,
    output reg  [                   7:0] m_axi_awlen,
    output reg  [AXI4_ADDRESS_WIDTH-1:0] m_axi_awaddr,
    output reg  [   AXI4_USER_WIDTH-1:0] m_axi_awuser,
    input  wire                          m_axi_awready,

    output reg                          m_axi_wvalid,
    output reg  [  AXI4_DATA_WIDTH-1:0] m_axi_wdata,
    output reg  [AXI4_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg                          m_axi_wlast,
    output reg  [  AXI4_USER_WIDTH-1:0] m_axi_wuser,
    input  wire                         m_axi_wready,

    input  wire                       m_axi_bvalid,
    input  wire [  AXI4_ID_WIDTH-1:0] m_axi_bid,
    input  wire [                1:0] m_axi_bresp,
    input  wire [AXI4_USER_WIDTH-1:0] m_axi_buser,
    output reg                        m_axi_bready,

    output reg                           m_axi_arvalid,
    output reg  [     AXI4_ID_WIDTH-1:0] m_axi_arid,
    output reg  [                   7:0] m_axi_arlen,
    output reg  [AXI4_ADDRESS_WIDTH-1:0] m_axi_araddr,
    output reg  [   AXI4_USER_WIDTH-1:0] m_axi_aruser,
    input  wire                          m_axi_arready,

    input  wire                       m_axi_rvalid,
    input  wire [  AXI4_ID_WIDTH-1:0] m_axi_rid,
    input  wire [AXI4_DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [                1:0] m_axi_rresp,
    input  wire                       m_axi_rlast,
    input  wire [AXI4_USER_WIDTH-1:0] m_axi_ruser,
    output reg                        m_axi_rready
);

  // =========================================================================
  //  Register byte addresses
  // =========================================================================
  localparam [AXI4_ADDRESS_WIDTH-1:0] ADDR_STATUS = 'h00;
  localparam [AXI4_ADDRESS_WIDTH-1:0] ADDR_CLKDIV = 'h04;
  localparam [AXI4_ADDRESS_WIDTH-1:0] ADDR_SPILEN = 'h10;
  localparam [AXI4_ADDRESS_WIDTH-1:0] ADDR_TX_FIFO = 'h20;
  localparam [AXI4_ADDRESS_WIDTH-1:0] ADDR_RX_FIFO = 'h40;

  // =========================================================================
  //  FSM states
  // =========================================================================
  typedef enum logic [4:0] {
    S_IDLE,
    // One-time CLKDIV init
    S_INIT_CLKDIV_AW,
    S_INIT_CLKDIV_W,
    S_INIT_CLKDIV_B,
    // Per-transaction
    S_WR_SPILEN_AW,
    S_WR_SPILEN_W,
    S_WR_SPILEN_B,
    S_WR_TXFIFO_AW,    // write path: push TX data
    S_WR_TXFIFO_W,
    S_WR_TXFIFO_B,
    S_WR_STATUS_AW,    // trigger rd/wr + set CS
    S_WR_STATUS_W,
    S_WR_STATUS_B,
    S_POLL_STATUS_AR,  // poll STATUS register
    S_POLL_STATUS_R,   // check if bit[0] (IDLE) is set
    S_RD_RXFIFO_AR,    // read path: fetch RX data
    S_RD_RXFIFO_R,
    S_DONE
  } state_t;

  state_t state_q, state_d;

  // =========================================================================
  //  Captured request & flags
  // =========================================================================
  reg [AXI4_ADDRESS_WIDTH-1:0] req_addr_q;
  reg [   AXI4_DATA_WIDTH-1:0] req_wdata_q;
  reg                          req_cs_q;
  reg                          req_write_q;
  reg                          clkdiv_done_q;
  reg                          axi_error_q;

  // =========================================================================
  //  AXI default outputs
  // =========================================================================
  always_comb begin
    m_axi_awvalid = 1'b0;
    m_axi_awid    = '0;
    m_axi_awlen   = 8'd0;
    m_axi_awaddr  = '0;
    m_axi_awuser  = '0;
    m_axi_wvalid  = 1'b0;
    m_axi_wdata   = '0;
    m_axi_wstrb   = '0;
    m_axi_wlast   = 1'b1;
    m_axi_wuser   = '0;
    m_axi_bready  = 1'b0;
    m_axi_arvalid = 1'b0;
    m_axi_arid    = '0;
    m_axi_arlen   = 8'd0;
    m_axi_araddr  = '0;
    m_axi_aruser  = '0;
    m_axi_rready  = 1'b0;
  end

  // =========================================================================
  //  FSM – next state & output logic
  // =========================================================================
  always_comb begin
    state_d = state_q;

    case (state_q)

      S_IDLE: begin
        if (req_valid_i) begin
          if (!clkdiv_done_q) state_d = S_INIT_CLKDIV_AW;
          else state_d = S_WR_SPILEN_AW;
        end
      end

      // =============== CLKDIV init (once) ================================
      S_INIT_CLKDIV_AW: begin
        m_axi_awvalid = 1'b1;
        m_axi_awaddr  = ADDR_CLKDIV;
        m_axi_wvalid  = 1'b1;
        m_axi_wdata   = {24'b0, SPI_CLKDIV};
        m_axi_wstrb   = 4'b0001;
        if (m_axi_awready && m_axi_wready) state_d = S_INIT_CLKDIV_B;
        else if (m_axi_awready) state_d = S_INIT_CLKDIV_W;
      end

      S_INIT_CLKDIV_W: begin
        m_axi_wvalid = 1'b1;
        m_axi_wdata  = {24'b0, SPI_CLKDIV};
        m_axi_wstrb  = 4'b0001;
        if (m_axi_wready) state_d = S_INIT_CLKDIV_B;
      end

      S_INIT_CLKDIV_B: begin
        m_axi_bready = 1'b1;
        if (m_axi_bvalid) state_d = S_WR_SPILEN_AW;
      end

      // =============== Write SPILEN ======================================
      // {data_len[15:0], 2'b0, addr_len[5:0], 2'b0, cmd_len[5:0]}
      // 32 bits of data, no command, no address phase
      S_WR_SPILEN_AW: begin
        m_axi_awvalid = 1'b1;
        m_axi_awaddr  = ADDR_SPILEN;
        m_axi_wvalid  = 1'b1;
        m_axi_wdata   = {16'd32, 2'b00, 6'd0, 2'b00, 6'd0};
        m_axi_wstrb   = 4'b1111;
        if (m_axi_awready && m_axi_wready) state_d = S_WR_SPILEN_B;
        else if (m_axi_awready) state_d = S_WR_SPILEN_W;
      end

      S_WR_SPILEN_W: begin
        m_axi_wvalid = 1'b1;
        m_axi_wdata  = {16'd32, 2'b00, 6'd0, 2'b00, 6'd0};
        m_axi_wstrb  = 4'b1111;
        if (m_axi_wready) state_d = S_WR_SPILEN_B;
      end

      S_WR_SPILEN_B: begin
        m_axi_bready = 1'b1;
        if (m_axi_bvalid) begin
          if (req_write_q) state_d = S_WR_TXFIFO_AW;
          else state_d = S_WR_STATUS_AW;
        end
      end

      // =============== Write TX FIFO (write path only) ===================
      S_WR_TXFIFO_AW: begin
        m_axi_awvalid = 1'b1;
        m_axi_awaddr  = ADDR_TX_FIFO;
        m_axi_wvalid  = 1'b1;
        m_axi_wdata   = req_wdata_q;
        m_axi_wstrb   = 4'b1111;
        if (m_axi_awready && m_axi_wready) state_d = S_WR_TXFIFO_B;
        else if (m_axi_awready) state_d = S_WR_TXFIFO_W;
      end

      S_WR_TXFIFO_W: begin
        m_axi_wvalid = 1'b1;
        m_axi_wdata  = req_wdata_q;
        m_axi_wstrb  = 4'b1111;
        if (m_axi_wready) state_d = S_WR_TXFIFO_B;
      end

      S_WR_TXFIFO_B: begin
        m_axi_bready = 1'b1;
        if (m_axi_bvalid) state_d = S_WR_STATUS_AW;
      end

      // =============== Write STATUS (CS select + rd/wr trigger) ==========
      // STATUS[0]=rd, [1]=wr, [11:8]=csreg
      S_WR_STATUS_AW: begin
        m_axi_awvalid = 1'b1;
        m_axi_awaddr = ADDR_STATUS;
        m_axi_wvalid = 1'b1;
        m_axi_wdata = {
          20'b0,
          req_cs_q ? 4'b0010 : 4'b0001,  // csreg [11:8]
          6'b0,
          req_write_q ? 2'b10 : 2'b01
        };  // [1]=wr, [0]=rd
        m_axi_wstrb = 4'b0011;
        if (m_axi_awready && m_axi_wready) state_d = S_WR_STATUS_B;
        else if (m_axi_awready) state_d = S_WR_STATUS_W;
      end

      S_WR_STATUS_W: begin
        m_axi_wvalid = 1'b1;
        m_axi_wdata  = {20'b0, req_cs_q ? 4'b0010 : 4'b0001, 6'b0, req_write_q ? 2'b10 : 2'b01};
        m_axi_wstrb  = 4'b0011;
        if (m_axi_wready) state_d = S_WR_STATUS_B;
      end

      S_WR_STATUS_B: begin
        m_axi_bready = 1'b1;
        if (m_axi_bvalid) state_d = S_POLL_STATUS_AR;
      end

      // =============== Poll STATUS until IDLE (bit[0]=1) =================
      S_POLL_STATUS_AR: begin
        m_axi_arvalid = 1'b1;
        m_axi_araddr  = ADDR_STATUS;
        if (m_axi_arready) state_d = S_POLL_STATUS_R;
      end

      S_POLL_STATUS_R: begin
        m_axi_rready = 1'b1;
        if (m_axi_rvalid) begin
          if (m_axi_rdata[0]) begin  // bit[0] = controller IDLE
            if (!req_write_q) state_d = S_RD_RXFIFO_AR;
            else state_d = S_DONE;
          end else begin
            state_d = S_POLL_STATUS_AR;  // not done, poll again
          end
        end
      end

      // =============== Read RX FIFO (read path only) =====================
      S_RD_RXFIFO_AR: begin
        m_axi_arvalid = 1'b1;
        m_axi_araddr  = ADDR_RX_FIFO;
        if (m_axi_arready) state_d = S_RD_RXFIFO_R;
      end

      S_RD_RXFIFO_R: begin
        m_axi_rready = 1'b1;
        if (m_axi_rvalid) state_d = S_DONE;
      end

      // =============== Done ==============================================
      S_DONE: begin
        state_d = S_IDLE;
      end

      default: state_d = S_IDLE;
    endcase
  end

  // =========================================================================
  //  Sequential logic
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q       <= S_IDLE;
      clkdiv_done_q <= 1'b0;
      req_addr_q    <= '0;
      req_wdata_q   <= '0;
      req_cs_q      <= 1'b0;
      req_write_q   <= 1'b0;
      axi_error_q   <= 1'b0;
      resp_rdata_o  <= '0;
      resp_done_o   <= 1'b0;
      resp_error_o  <= 1'b0;
      busy_o        <= 1'b0;
    end else begin
      state_q      <= state_d;
      resp_done_o  <= 1'b0;
      resp_error_o <= 1'b0;

      // Capture request
      if (state_q == S_IDLE && req_valid_i) begin
        req_addr_q  <= req_addr_i;
        req_wdata_q <= req_wdata_i;
        req_cs_q    <= req_cs_i;
        req_write_q <= req_write_i;
        busy_o      <= 1'b1;
        axi_error_q <= 1'b0;
      end

      // Track clkdiv init
      if (state_q == S_INIT_CLKDIV_B && m_axi_bvalid) clkdiv_done_q <= 1'b1;

      // Capture AXI errors
      if (m_axi_bvalid && m_axi_bready && (m_axi_bresp != 2'b00)) axi_error_q <= 1'b1;
      if (m_axi_rvalid && m_axi_rready && (m_axi_rresp != 2'b00)) axi_error_q <= 1'b1;

      // Capture RX read data
      if (state_q == S_RD_RXFIFO_R && m_axi_rvalid)
        resp_rdata_o <= m_axi_rdata[AXI4_DATA_WIDTH-1:0];

      // Done pulse
      if (state_q == S_DONE) begin
        resp_done_o  <= 1'b1;
        resp_error_o <= axi_error_q;
        busy_o       <= 1'b0;
      end
    end
  end

endmodule

