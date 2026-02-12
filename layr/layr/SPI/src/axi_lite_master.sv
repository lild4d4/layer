// axi_lite_master.sv
//
// Simple AXI4 single-beat master wrapper intended to drive the `axi_spi_master`
// IP core (AXI4 slave).
//
// Your FSM talks to a small req/resp interface. This module turns each request
// into exactly one AXI transaction:
//   * write -> AW + W + B (single beat, AWLEN=0)
//   * read  -> AR + R     (single beat, ARLEN=0)
//
// KISS goals
// ---------
// * One outstanding request at a time.
// * No arbitration.
// * Active-high reset.
// * Small optional init sequence after reset:
//     - program CLKDIV
//     - optionally pulse STATUS[4]=1 (swrst)
//
// Chip-select handling
// --------------------
// AXI has no chip-select. The SPI core exposes `spi_csreg` in STATUS[11:8].
// For convenience, this wrapper overwrites STATUS[11:8] on STATUS writes,
// based on req_cs_i:
//   req_cs_i=0 -> CS_EEPROM
//   req_cs_i=1 -> CS_NFC

module axi_lite_master #(
    parameter int unsigned AXI4_ADDRESS_WIDTH = 32,
    parameter int unsigned AXI4_DATA_WIDTH    = 32,
    parameter int unsigned AXI4_ID_WIDTH      = 16,
    parameter int unsigned AXI4_USER_WIDTH    = 4,

    // If you provide offsets on req_addr_i, set AXI_BASE_ADDR to the SPI core base.
    // If you already provide absolute addresses, leave it 0.
    parameter logic [AXI4_ADDRESS_WIDTH-1:0] AXI_BASE_ADDR = '0,

    // SPI core register offsets (relative to AXI_BASE_ADDR)
    parameter logic [AXI4_ADDRESS_WIDTH-1:0] STATUS_OFFSET = 32'h00,
    parameter logic [AXI4_ADDRESS_WIDTH-1:0] CLKDIV_OFFSET = 32'h04,

    // Map req_cs_i to the SPI core's one-hot `spi_csreg` field.
    // Default: 0 -> CS0 (EEPROM), 1 -> CS1 (NFC)
    parameter logic [3:0] CS_EEPROM = 4'b0001,
    parameter logic [3:0] CS_NFC    = 4'b0010,

    // Very small init sequence after reset
    parameter bit         INIT_ENABLE   = 1'b1,
    parameter logic [7:0] INIT_CLKDIV   = 8'd10,
    parameter bit         INIT_DO_SWRST = 1'b1
) (
    input logic clk,
    input logic rst,  // active-high reset

    // ── Simple interface your FSM talks to ────────────────────────────────
    input logic [AXI4_ADDRESS_WIDTH-1:0] req_addr_i,
    input logic [   AXI4_DATA_WIDTH-1:0] req_wdata_i,
    input logic                          req_cs_i,     // 1=nfc, 0=eeprom
    input logic                          req_write_i,  // 1=write, 0=read
    input logic                          req_valid_i,  // pulse to start

    output logic [AXI4_DATA_WIDTH-1:0] resp_rdata_o,
    output logic                       resp_done_o,   // pulse when complete
    output logic                       resp_error_o,  // pulse on AXI error
    output logic                       busy_o,

    // ── AXI4 master interface towards the SPI IP core ─────────────────────
    output logic                          m_axi_awvalid,
    output logic [     AXI4_ID_WIDTH-1:0] m_axi_awid,
    output logic [                   7:0] m_axi_awlen,
    output logic [AXI4_ADDRESS_WIDTH-1:0] m_axi_awaddr,
    output logic [   AXI4_USER_WIDTH-1:0] m_axi_awuser,
    input  logic                          m_axi_awready,

    output logic                         m_axi_wvalid,
    output logic [  AXI4_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [AXI4_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                         m_axi_wlast,
    output logic [  AXI4_USER_WIDTH-1:0] m_axi_wuser,
    input  logic                         m_axi_wready,

    input  logic                       m_axi_bvalid,
    input  logic [  AXI4_ID_WIDTH-1:0] m_axi_bid,
    input  logic [                1:0] m_axi_bresp,
    input  logic [AXI4_USER_WIDTH-1:0] m_axi_buser,
    output logic                       m_axi_bready,

    output logic                          m_axi_arvalid,
    output logic [     AXI4_ID_WIDTH-1:0] m_axi_arid,
    output logic [                   7:0] m_axi_arlen,
    output logic [AXI4_ADDRESS_WIDTH-1:0] m_axi_araddr,
    output logic [   AXI4_USER_WIDTH-1:0] m_axi_aruser,
    input  logic                          m_axi_arready,

    input  logic                       m_axi_rvalid,
    input  logic [  AXI4_ID_WIDTH-1:0] m_axi_rid,
    input  logic [AXI4_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [                1:0] m_axi_rresp,
    input  logic                       m_axi_rlast,
    input  logic [AXI4_USER_WIDTH-1:0] m_axi_ruser,
    output logic                       m_axi_rready
);

  // ----------------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------------
  function automatic logic [AXI4_ADDRESS_WIDTH-1:0] eff_addr(
      input logic [AXI4_ADDRESS_WIDTH-1:0] off);
    eff_addr = AXI_BASE_ADDR + off;
  endfunction

  function automatic logic [AXI4_DATA_WIDTH-1:0] inject_cs_into_status(
      input logic [AXI4_DATA_WIDTH-1:0] wdata_in, input logic cs_sel);
    logic [AXI4_DATA_WIDTH-1:0] tmp;
    logic [                3:0] csreg;
    begin
      tmp   = wdata_in;
      csreg = cs_sel ? CS_NFC : CS_EEPROM;
      if (AXI4_DATA_WIDTH >= 12) tmp[11:8] = csreg;
      inject_cs_into_status = tmp;
    end
  endfunction

  // ----------------------------------------------------------------------
  // Constant AXI fields (single-beat)
  // ----------------------------------------------------------------------
  always_comb begin
    m_axi_awid   = '0;
    m_axi_awlen  = 8'd0;
    m_axi_awuser = '0;

    m_axi_wstrb  = {AXI4_DATA_WIDTH / 8{1'b1}};
    m_axi_wlast  = 1'b1;
    m_axi_wuser  = '0;

    m_axi_arid   = '0;
    m_axi_arlen  = 8'd0;
    m_axi_aruser = '0;
  end

  // ----------------------------------------------------------------------
  // Init sequencing
  // ----------------------------------------------------------------------
  typedef enum logic [1:0] {
    INIT_DONE,
    INIT_SET_CLKDIV,
    INIT_PULSE_SWRST
  } init_state_t;

  init_state_t init_state;

  // ----------------------------------------------------------------------
  // Main transaction FSM
  // ----------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_W_AW_W,
    ST_W_B,
    ST_R_AR,
    ST_R_R
  } state_t;

  state_t state;

  // Track per-channel handshakes for write
  logic aw_done, w_done;

  // Mark whether current transaction is init (suppress resp pulses)
  logic cur_is_init_q;

  // ----------------------------------------------------------------------
  // FSM
  // ----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      state         <= ST_IDLE;
      init_state    <= (INIT_ENABLE ? INIT_SET_CLKDIV : INIT_DONE);

      busy_o        <= (INIT_ENABLE ? 1'b1 : 1'b0);
      resp_done_o   <= 1'b0;
      resp_error_o  <= 1'b0;
      resp_rdata_o  <= '0;

      m_axi_awvalid <= 1'b0;
      m_axi_awaddr  <= '0;
      m_axi_wvalid  <= 1'b0;
      m_axi_wdata   <= '0;
      m_axi_bready  <= 1'b0;

      m_axi_arvalid <= 1'b0;
      m_axi_araddr  <= '0;
      m_axi_rready  <= 1'b0;

      aw_done       <= 1'b0;
      w_done        <= 1'b0;
      cur_is_init_q <= 1'b0;

    end else begin
      // default: pulses low unless set in this cycle
      resp_done_o  <= 1'b0;
      resp_error_o <= 1'b0;

      case (state)
        // ------------------------------------------------------------
        // IDLE: run init (if pending) otherwise accept external req
        // ------------------------------------------------------------
        ST_IDLE: begin
          m_axi_bready <= 1'b0;
          m_axi_rready <= 1'b0;
          aw_done      <= 1'b0;
          w_done       <= 1'b0;

          if (init_state != INIT_DONE) begin
            busy_o        <= 1'b1;
            cur_is_init_q <= 1'b1;

            // Init step 1: program CLKDIV
            if (init_state == INIT_SET_CLKDIV) begin
              m_axi_awaddr  <= eff_addr(CLKDIV_OFFSET);
              m_axi_awvalid <= 1'b1;
              m_axi_wdata   <= {{(AXI4_DATA_WIDTH - 8) {1'b0}}, INIT_CLKDIV};
              m_axi_wvalid  <= 1'b1;
              state         <= ST_W_AW_W;
            end  // Init step 2: optional pulse STATUS[4]=1
            else if (init_state == INIT_PULSE_SWRST) begin
              m_axi_awaddr  <= eff_addr(STATUS_OFFSET);
              m_axi_awvalid <= 1'b1;
              m_axi_wdata   <= inject_cs_into_status((AXI4_DATA_WIDTH'(1) << 4), 1'b0);
              m_axi_wvalid  <= 1'b1;
              state         <= ST_W_AW_W;
            end

          end else begin
            // No init pending
            cur_is_init_q <= 1'b0;
            busy_o        <= 1'b0;

            if (req_valid_i) begin
              busy_o <= 1'b1;

              if (req_write_i) begin
                m_axi_awaddr  <= eff_addr(req_addr_i);
                m_axi_awvalid <= 1'b1;

                if (eff_addr(req_addr_i) == eff_addr(STATUS_OFFSET))
                  m_axi_wdata <= inject_cs_into_status(req_wdata_i, req_cs_i);
                else m_axi_wdata <= req_wdata_i;

                m_axi_wvalid <= 1'b1;
                state        <= ST_W_AW_W;

              end else begin
                m_axi_araddr  <= eff_addr(req_addr_i);
                m_axi_arvalid <= 1'b1;
                state         <= ST_R_AR;
              end
            end
          end
        end

        // ------------------------------------------------------------
        // WRITE: AW/W phase
        // ------------------------------------------------------------
        ST_W_AW_W: begin
          if (m_axi_awvalid && m_axi_awready) begin
            m_axi_awvalid <= 1'b0;
            aw_done       <= 1'b1;
          end
          if (m_axi_wvalid && m_axi_wready) begin
            m_axi_wvalid <= 1'b0;
            w_done       <= 1'b1;
          end

          if ( (aw_done || (m_axi_awvalid && m_axi_awready)) &&
               (w_done  || (m_axi_wvalid  && m_axi_wready )) ) begin
            m_axi_bready <= 1'b1;
            state        <= ST_W_B;
          end
        end

        // ------------------------------------------------------------
        // WRITE: B response
        // ------------------------------------------------------------
        ST_W_B: begin
          if (m_axi_bvalid && m_axi_bready) begin
            m_axi_bready <= 1'b0;

            if (cur_is_init_q) begin
              // Advance init sequencer
              if (init_state == INIT_SET_CLKDIV) begin
                init_state <= (INIT_DO_SWRST ? INIT_PULSE_SWRST : INIT_DONE);
              end else if (init_state == INIT_PULSE_SWRST) begin
                init_state <= INIT_DONE;
              end
              // keep busy until init_state becomes INIT_DONE (handled in ST_IDLE)

            end else begin
              busy_o       <= 1'b0;
              resp_done_o  <= 1'b1;
              resp_error_o <= (m_axi_bresp != 2'b00);
            end

            state <= ST_IDLE;
          end
        end

        // ------------------------------------------------------------
        // READ: AR phase
        // ------------------------------------------------------------
        ST_R_AR: begin
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b1;
            state         <= ST_R_R;
          end
        end

        // ------------------------------------------------------------
        // READ: R beat
        // ------------------------------------------------------------
        ST_R_R: begin
          if (m_axi_rvalid && m_axi_rready) begin
            m_axi_rready <= 1'b0;
            resp_rdata_o <= m_axi_rdata;

            busy_o       <= 1'b0;
            resp_done_o  <= 1'b1;
            resp_error_o <= (m_axi_rresp != 2'b00) || (!m_axi_rlast);

            state        <= ST_IDLE;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
