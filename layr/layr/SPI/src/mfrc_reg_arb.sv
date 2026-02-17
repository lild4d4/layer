// reg_arb – round-robin arbiter for MFRC register interface clients
//
// Two clients share a single mfrc_reg_if instance:
//   - Client A: FSM (for initialization: soft reset, register writes, antenna enable)
//   - Client B: mfrc_core (for transceive operations)
//
// FSM (Client A) has priority until init is complete, then round-robin arbitration.
// After init_done, both clients are served in round-robin fashion.
//
// Client interface mimics mfrc_reg_if: req_valid/req_ready, req_*, resp_*

module mfrc_reg_arb (
    input wire clk,
    input wire rst,

    // FSM (Client A - initialization)
    input  wire         a_req_valid,
    output wire         a_req_ready,
    input  wire         a_req_write,
    input  wire [  5:0] a_req_addr,
    input  wire [  4:0] a_req_len,
    input  wire [255:0] a_req_wdata,

    output wire         a_resp_valid,
    output wire [255:0] a_resp_rdata,
    output wire         a_resp_ok,

    // mfrc_core (Client B - transceive)
    input  wire         b_req_valid,
    output wire         b_req_ready,
    input  wire         b_req_write,
    input  wire [  5:0] b_req_addr,
    input  wire [  4:0] b_req_len,
    input  wire [255:0] b_req_wdata,

    output wire         b_resp_valid,
    output wire [255:0] b_resp_rdata,
    output wire         b_resp_ok,

    // To mfrc_reg_if
    output wire         m_req_valid,
    input  wire         m_req_ready,
    output wire         m_req_write,
    output wire [  5:0] m_req_addr,
    output wire [  4:0] m_req_len,
    output wire [255:0] m_req_wdata,

    input wire         m_resp_valid,
    input wire [255:0] m_resp_rdata,
    input wire         m_resp_ok,

    // Control
    input wire init_done  // 1 = initialization complete, enables round-robin
);

  // Arbitration state
  reg          busy;
  reg          grant_hold;  // 0 = client A, 1 = client B
  reg          rr_pref;  // round-robin preference

  // Pending request latches
  reg          a_pending;
  reg          a_pending_write;
  reg  [  5:0] a_pending_addr;
  reg  [  4:0] a_pending_len;
  reg  [255:0] a_pending_wdata;

  reg          b_pending;
  reg          b_pending_write;
  reg  [  5:0] b_pending_addr;
  reg  [  4:0] b_pending_len;
  reg  [255:0] b_pending_wdata;

  // Held transaction data
  reg          held_write;
  reg  [  5:0] held_addr;
  reg  [  4:0] held_len;
  reg  [255:0] held_wdata;

  // Effective request signals
  wire         a_req = a_req_valid | a_pending;
  wire         b_req = b_req_valid | b_pending;

  // Arbitration: if init not done, A always wins. Otherwise round-robin.
  wire         grant_pick;
  assign grant_pick = init_done ? 
                      (a_req && b_req ? rr_pref : (b_req && !a_req)) :
                      1'b0;  // A always wins during init

  // Effective data
  wire [5:0] a_eff_addr = a_req_valid ? a_req_addr : a_pending_addr;
  wire [4:0] a_eff_len = a_req_valid ? a_req_len : a_pending_len;
  wire [255:0] a_eff_wdata = a_req_valid ? a_req_wdata : a_pending_wdata;
  wire a_eff_write = a_req_valid ? a_req_write : a_pending_write;

  wire [5:0] b_eff_addr = b_req_valid ? b_req_addr : b_pending_addr;
  wire [4:0] b_eff_len = b_req_valid ? b_req_len : b_pending_len;
  wire [255:0] b_eff_wdata = b_req_valid ? b_req_wdata : b_pending_wdata;
  wire b_eff_write = b_req_valid ? b_req_write : b_pending_write;

  // Winner's data
  wire [5:0] win_addr = (grant_pick == 1'b0) ? a_eff_addr : b_eff_addr;
  wire [4:0] win_len = (grant_pick == 1'b0) ? a_eff_len : b_eff_len;
  wire [255:0] win_wdata = (grant_pick == 1'b0) ? a_eff_wdata : b_eff_wdata;
  wire win_write = (grant_pick == 1'b0) ? a_eff_write : b_eff_write;

  // Master signals
  wire master_req = a_req || b_req;
  assign m_req_valid = (!busy) && master_req;
  assign m_req_addr = busy ? held_addr : win_addr;
  assign m_req_len = busy ? held_len : win_len;
  assign m_req_wdata = busy ? held_wdata : win_wdata;
  assign m_req_write = busy ? held_write : win_write;

  // Client ready (not busy and request can be accepted)
  assign a_req_ready = !busy && (!init_done || (init_done && grant_pick != 1'b0));
  assign b_req_ready = !busy && init_done && (grant_pick == 1'b0);

  // Response routing
  assign a_resp_valid = busy && (grant_hold == 1'b0) && m_resp_valid;
  assign a_resp_rdata = m_resp_rdata;
  assign a_resp_ok = m_resp_ok;

  assign b_resp_valid = busy && (grant_hold == 1'b1) && m_resp_valid;
  assign b_resp_rdata = m_resp_rdata;
  assign b_resp_ok = m_resp_ok;

  // State update
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      busy            <= 1'b0;
      grant_hold      <= 1'b0;
      rr_pref         <= 1'b0;
      held_addr       <= 6'd0;
      held_len        <= 4'd0;
      held_wdata      <= 256'd0;
      held_write      <= 1'b0;

      a_pending       <= 1'b0;
      a_pending_addr  <= 6'd0;
      a_pending_len   <= 4'd0;
      a_pending_wdata <= 256'd0;
      a_pending_write <= 1'b0;

      b_pending       <= 1'b0;
      b_pending_addr  <= 6'd0;
      b_pending_len   <= 4'd0;
      b_pending_wdata <= 256'd0;
      b_pending_write <= 1'b0;
    end else begin
      // Latch pending requests from A
      if (a_req_valid && !a_req_ready) begin
        a_pending       <= 1'b1;
        a_pending_addr  <= a_req_addr;
        a_pending_len   <= a_req_len;
        a_pending_wdata <= a_req_wdata;
        a_pending_write <= a_req_write;
      end else if (a_pending && m_resp_valid) begin
        a_pending <= 1'b0;
      end

      // Latch pending requests from B
      if (b_req_valid && !b_req_ready) begin
        b_pending       <= 1'b1;
        b_pending_addr  <= b_req_addr;
        b_pending_len   <= b_req_len;
        b_pending_wdata <= b_req_wdata;
        b_pending_write <= b_req_write;
      end else if (b_pending && m_resp_valid) begin
        b_pending <= 1'b0;
      end

      // Grant: latch winner's data and mark busy
      if (m_req_valid && !busy) begin
        busy       <= 1'b1;
        grant_hold <= grant_pick;
        if (init_done) begin
          rr_pref <= ~grant_pick;
        end
        held_addr  <= win_addr;
        held_len   <= win_len;
        held_wdata <= win_wdata;
        held_write <= win_write;
      end

      // Transaction complete
      if (busy && m_resp_valid) begin
        busy <= 1'b0;
      end
    end
  end

endmodule
