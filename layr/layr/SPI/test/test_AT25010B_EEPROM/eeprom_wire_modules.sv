// Testbench wrapper: wires eeprom_spi → axi_lite_master → axi_spi_master
// All three modules share a single clock and reset.

module eeprom_wire_modules (
    input wire clk,
    input wire rst_n,

    // ── Simple command interface (driven by cocotb test) ────────
    input  wire       cmd_valid,
    input  wire       cmd_write,
    input  wire [6:0] cmd_addr,
    input  wire [7:0] cmd_wdata,
    output wire [7:0] cmd_rdata,
    output wire       cmd_done,
    output wire       cmd_busy,

    // ── SPI pins (connected to AT25010B mock) ───────────────────
    output wire spi_clk,
    output wire spi_csn0,  // CS0 → EEPROM
    output wire spi_sdo0,  // MOSI
    input  wire spi_sdi0   // MISO
);

  // ── Internal AXI wires: eeprom_spi ↔ axi_lite_master ────────
  wire [31:0] axi_req_addr;
  wire [31:0] axi_req_wdata;
  wire        axi_req_write;
  wire        axi_req_valid;
  wire [31:0] axi_resp_rdata;
  wire        axi_resp_done;
  wire        axi_busy;

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
  wire [31:0] m_axi_rdata;
  wire [ 1:0] m_axi_rresp;
  wire        m_axi_rlast;
  wire        m_axi_rvalid;
  wire        m_axi_rready;

  // Unused SPI outputs (quad-SPI; we only use SDO0/SDI0)
  wire spi_csn1, spi_csn2, spi_csn3;
  wire [1:0] spi_mode;
  wire spi_sdo1, spi_sdo2, spi_sdo3;
  wire [1:0] events_o;

  // ── eeprom_spi (FSM) ─────────────────────────────────────────
  eeprom_spi u_eeprom_spi (
      .clk  (clk),
      .rst_n(rst_n),

      .cmd_valid(cmd_valid),
      .cmd_write(cmd_write),
      .cmd_addr (cmd_addr),
      .cmd_wdata(cmd_wdata),
      .cmd_rdata(cmd_rdata),
      .cmd_done (cmd_done),
      .cmd_busy (cmd_busy),

      .axi_req_addr  (axi_req_addr),
      .axi_req_wdata (axi_req_wdata),
      .axi_req_write (axi_req_write),
      .axi_req_valid (axi_req_valid),
      .axi_resp_rdata(axi_resp_rdata),
      .axi_resp_done (axi_resp_done),
      .axi_busy      (axi_busy)
  );

  // ── axi_lite_master ──────────────────────────────────────────
  axi_lite_master #(
      .AXI4_ADDRESS_WIDTH(32),
      .AXI4_DATA_WIDTH   (32),
      .AXI4_ID_WIDTH     (16),
      .AXI4_USER_WIDTH   (4)
  ) u_axi_master (
      .clk (clk),
      .rst (~rst_n),

      .req_addr_i  (axi_req_addr),
      .req_wdata_i (axi_req_wdata),
      .req_cs_i    (1'b0),          // always EEPROM (CS0)
      .req_write_i (axi_req_write),
      .req_valid_i (axi_req_valid),
      .resp_rdata_o(axi_resp_rdata),
      .resp_done_o (axi_resp_done),
      .resp_error_o(),                // not used by eeprom_spi FSM
      .busy_o      (axi_busy),

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
      .m_axi_bvalid(m_axi_bvalid),
      .m_axi_bready(m_axi_bready),

      .m_axi_araddr (m_axi_araddr),
      .m_axi_arid   (m_axi_arid),
      .m_axi_arlen  (m_axi_arlen),
      .m_axi_aruser (m_axi_aruser),
      .m_axi_arvalid(m_axi_arvalid),
      .m_axi_arready(m_axi_arready),

      .m_axi_rdata (m_axi_rdata),
      .m_axi_rresp (m_axi_rresp),
      .m_axi_rlast (m_axi_rlast),
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
      .s_axi_aresetn(rst_n),

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
      .s_axi_buser (),
      .s_axi_bready(m_axi_bready),

      .s_axi_arvalid(m_axi_arvalid),
      .s_axi_arid   (m_axi_arid),
      .s_axi_arlen  (m_axi_arlen),
      .s_axi_araddr (m_axi_araddr),
      .s_axi_aruser (m_axi_aruser),
      .s_axi_arready(m_axi_arready),

      .s_axi_rvalid(m_axi_rvalid),
      .s_axi_rid   (),
      .s_axi_rdata (m_axi_rdata),
      .s_axi_rresp (m_axi_rresp),
      .s_axi_rlast (m_axi_rlast),
      .s_axi_ruser (),
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
