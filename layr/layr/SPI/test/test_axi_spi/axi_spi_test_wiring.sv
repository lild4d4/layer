// Testbench wrapper: wires eeprom_spi → axi_lite_master → axi_spi_master
// All three modules share a single clock and reset.

`define AXI4_DATA_WIDTH 32
`define AXI4_ADDRESS_WIDTH 32

module axi_spi_test_wiring (
    input wire clk,
    input wire rst_n,

    // ── driven by cocotb test ────────
    input  wire [`AXI4_ADDRESS_WIDTH-1:0] req_addr_i,
    input  wire [   `AXI4_DATA_WIDTH-1:0] req_wdata_i,
    input  wire                           req_write_i,   // 1=write, 0=read
    input  wire                           req_cs_i,      // 1=nfc, 0=eeprom
    input  wire                           req_valid_i,   // pulse to start
    output wire [   `AXI4_DATA_WIDTH-1:0] resp_rdata_o,
    output wire                           resp_done_o,   // pulse when complete
    output wire                           resp_error_o,  // pulse on AXI error
    output wire                           busy_o,


    // ── SPI pins (connected to AT25010B mock) ───────────────────
    output wire spi_clk,
    output wire spi_csn0,  // CS0 → EEPROM
    output wire spi_sdo0,  // MOSI
    input  wire spi_sdi0   // MISO
);
  // ── AXI4 bus: axi_lite_master ↔ axi_spi_master ──────────────
  // Write address channel
  wire [31:0] m_axi_awaddr;
  wire [15:0] m_axi_awid;
  wire [ 7:0] m_axi_awlen;
  wire [ 3:0] m_axi_awuser;
  wire        m_axi_awvalid;
  wire        m_axi_awready;

  // Write data channel
  wire [31:0] m_axi_wdata;
  wire [ 3:0] m_axi_wstrb;
  wire        m_axi_wlast;
  wire [ 3:0] m_axi_wuser;
  wire        m_axi_wvalid;
  wire        m_axi_wready;

  // Write response channel
  wire [15:0] m_axi_bid;
  wire [ 1:0] m_axi_bresp;
  wire [ 3:0] m_axi_buser;
  wire        m_axi_bvalid;
  wire        m_axi_bready;

  // Read address channel
  wire [31:0] m_axi_araddr;
  wire [15:0] m_axi_arid;
  wire [ 7:0] m_axi_arlen;
  wire [ 3:0] m_axi_aruser;
  wire        m_axi_arvalid;
  wire        m_axi_arready;

  // Read data channel
  wire [15:0] m_axi_rid;
  wire [31:0] m_axi_rdata;
  wire [ 1:0] m_axi_rresp;
  wire        m_axi_rlast;
  wire [ 3:0] m_axi_ruser;
  wire        m_axi_rvalid;
  wire        m_axi_rready;

  // Unused SPI outputs (quad-SPI; we only use SDO0/SDI0)
  wire spi_csn1, spi_csn2, spi_csn3;
  wire [1:0] spi_mode;
  wire spi_sdo1, spi_sdo2, spi_sdo3;
  wire [1:0] events_o;

  // ── axi_lite_master ──────────────────────────────────────────
  axi_lite_master #(
      .AXI4_ADDRESS_WIDTH(32),
      .AXI4_DATA_WIDTH   (32),
      .AXI4_ID_WIDTH     (16),
      .AXI4_USER_WIDTH   (4)
  ) u_axi_master (
      .clk(clk),
      .rst(rst_n),

      .req_addr_i  (req_addr_i),
      .req_wdata_i (req_wdata_i),
      .req_cs_i    (req_cs_i),
      .req_write_i (req_write_i),
      .req_valid_i (req_valid_i),
      .resp_rdata_o(resp_rdata_o),
      .resp_done_o (resp_done_o),
      .resp_error_o(resp_error_o),
      .busy_o      (busy_o),

      .m_axi_awaddr (m_axi_awaddr),
      .m_axi_awid   (m_axi_awid),
      .m_axi_awlen  (m_axi_awlen),
      .m_axi_awuser (m_axi_awuser),
      .m_axi_awvalid(m_axi_awvalid),
      .m_axi_awready(m_axi_awready),

      .m_axi_wdata (m_axi_wdata),
      .m_axi_wstrb (m_axi_wstrb),
      .m_axi_wlast (m_axi_wlast),
      .m_axi_wuser (m_axi_wuser),
      .m_axi_wvalid(m_axi_wvalid),
      .m_axi_wready(m_axi_wready),

      .m_axi_bid   (m_axi_bid),
      .m_axi_bresp (m_axi_bresp),
      .m_axi_buser (m_axi_buser),
      .m_axi_bvalid(m_axi_bvalid),
      .m_axi_bready(m_axi_bready),

      .m_axi_araddr (m_axi_araddr),
      .m_axi_arid   (m_axi_arid),
      .m_axi_arlen  (m_axi_arlen),
      .m_axi_aruser (m_axi_aruser),
      .m_axi_arvalid(m_axi_arvalid),
      .m_axi_arready(m_axi_arready),

      .m_axi_rdata (m_axi_rdata),
      .m_axi_rid   (m_axi_rid),
      .m_axi_rresp (m_axi_rresp),
      .m_axi_rlast (m_axi_rlast),
      .m_axi_ruser (m_axi_ruser),
      .m_axi_rvalid(m_axi_rvalid),
      .m_axi_rready(m_axi_rready)
  );

  // ── axi_spi_master (PULP IP) ─────────────────────────────────
  axi_spi_master #(
      .AXI4_ADDRESS_WIDTH(32),
      .AXI4_RDATA_WIDTH  (32),
      .AXI4_WDATA_WIDTH  (32),
      .AXI4_USER_WIDTH   (4),
      .AXI4_ID_WIDTH     (16),
      .BUFFER_DEPTH      (8)
  ) u_spi_master (
      .s_axi_aclk   (clk),
      .s_axi_aresetn(~rst_n),

      .s_axi_awvalid(m_axi_awvalid),
      .s_axi_awid   (m_axi_awid),
      .s_axi_awlen  (m_axi_awlen),
      .s_axi_awaddr (m_axi_awaddr),
      .s_axi_awuser (m_axi_awuser),
      .s_axi_awready(m_axi_awready),

      .s_axi_wvalid(m_axi_wvalid),
      .s_axi_wdata (m_axi_wdata),
      .s_axi_wstrb (m_axi_wstrb),
      .s_axi_wlast (m_axi_wlast),
      .s_axi_wuser (m_axi_wuser),
      .s_axi_wready(m_axi_wready),

      .s_axi_bvalid(m_axi_bvalid),
      .s_axi_bid   (m_axi_bid),
      .s_axi_bresp (m_axi_bresp),
      .s_axi_buser (m_axi_buser),
      .s_axi_bready(m_axi_bready),

      .s_axi_arvalid(m_axi_arvalid),
      .s_axi_arid   (m_axi_arid),
      .s_axi_arlen  (m_axi_arlen),
      .s_axi_araddr (m_axi_araddr),
      .s_axi_aruser (m_axi_aruser),
      .s_axi_arready(m_axi_arready),

      .s_axi_rvalid(m_axi_rvalid),
      .s_axi_rid   (m_axi_rid),
      .s_axi_rdata (m_axi_rdata),
      .s_axi_rresp (m_axi_rresp),
      .s_axi_rlast (m_axi_rlast),
      .s_axi_ruser (m_axi_ruser),
      .s_axi_rready(m_axi_rready),

      .events_o(events_o),

      .spi_clk (spi_clk),
      .spi_csn0(spi_csn0),
      .spi_csn1(spi_csn1),
      .spi_csn2(spi_csn2),
      .spi_csn3(spi_csn3),
      .spi_mode(spi_mode),
      .spi_sdo0(spi_sdo0),
      .spi_sdo1(spi_sdo1),
      .spi_sdo2(spi_sdo2),
      .spi_sdo3(spi_sdo3),
      .spi_sdi0(spi_sdi0),
      .spi_sdi1(1'b0),
      .spi_sdi2(1'b0),
      .spi_sdi3(1'b0)
  );

endmodule
