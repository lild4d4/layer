// mfrc_reg_arb – simple priority arbiter for MFRC register interface
//
// Client A always has priority over Client B.
// No round-robin, no pending latches. If A wants the bus, B waits.

module mfrc_reg_arb (
    input wire clk,
    input wire rst,

    // Client A (priority)
    input  wire         a_req_valid,
    output wire         a_req_ready,
    input  wire         a_req_write,
    input  wire [  5:0] a_req_addr,
    input  wire [  4:0] a_req_len,
    input  wire [255:0] a_req_wdata,

    output wire         a_resp_valid,
    output wire [255:0] a_resp_rdata,
    output wire         a_resp_ok,

    // Client B
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
    input wire         m_resp_ok
);

  // grant_hold: which client owns the in-flight transaction
  // 0 = A, 1 = B
  reg  busy;
  reg  grant_hold;

  // A wins if requesting; B gets the bus only if A is idle
  wire grant_a = a_req_valid;
  wire grant_b = b_req_valid && !a_req_valid;

  // Request to master: pass through winner's signals when not busy
  assign m_req_valid = !busy && (a_req_valid || b_req_valid);
  assign m_req_write = grant_a ? a_req_write : b_req_write;
  assign m_req_addr  = grant_a ? a_req_addr  : b_req_addr;
  assign m_req_len   = grant_a ? a_req_len   : b_req_len;
  assign m_req_wdata = grant_a ? a_req_wdata : b_req_wdata;

  // Ready back to clients
  assign a_req_ready = !busy && m_req_ready;
  assign b_req_ready = !busy && m_req_ready && !a_req_valid;

  // Response routing based on who owns the in-flight transaction
  assign a_resp_valid = busy && !grant_hold && m_resp_valid;
  assign b_resp_valid = busy &&  grant_hold && m_resp_valid;
  assign a_resp_rdata = m_resp_rdata;
  assign b_resp_rdata = m_resp_rdata;
  assign a_resp_ok    = m_resp_ok;
  assign b_resp_ok    = m_resp_ok;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      busy       <= 1'b0;
      grant_hold <= 1'b0;
    end else begin
      if (!busy && m_req_valid && m_req_ready) begin
        busy       <= 1'b1;
        grant_hold <= grant_b;
      end
      if (busy && m_resp_valid) begin
        busy <= 1'b0;
      end
    end
  end

endmodule

