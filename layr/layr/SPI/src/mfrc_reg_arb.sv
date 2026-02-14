// mfrc_reg_arb_rr – minimal 2-to-1 round-robin arbiter for mfrc_reg_if
//
// Two clients (A,B) share a single mfrc_reg_if request/response interface.
// Assumes ONE outstanding request at a time (which matches mfrc_reg_if).
//
// Request handshake: req_valid && req_ready
// Response: resp_valid pulse (no resp_ready)
//
// Round-robin policy when both A and B request at the same time.

module mfrc_reg_arb (
    input  wire         clk,
    input  wire         rst,

    // ---------------- Client A ----------------
    input  wire         a_req_valid,
    output wire         a_req_ready,
    input  wire         a_req_write,
    input  wire [5:0]   a_req_addr,
    input  wire [4:0]   a_req_len,
    input  wire [255:0] a_req_wdata,

    output wire         a_resp_valid,
    output wire [255:0] a_resp_rdata,
    output wire         a_resp_ok,

    // ---------------- Client B ----------------
    input  wire         b_req_valid,
    output wire         b_req_ready,
    input  wire         b_req_write,
    input  wire [5:0]   b_req_addr,
    input  wire [4:0]   b_req_len,
    input  wire [255:0] b_req_wdata,

    output wire         b_resp_valid,
    output wire [255:0] b_resp_rdata,
    output wire         b_resp_ok,

    // ---------------- Shared reg_if ----------------
    output wire         s_req_valid,
    input  wire         s_req_ready,
    output wire         s_req_write,
    output wire [5:0]   s_req_addr,
    output wire [4:0]   s_req_len,
    output wire [255:0] s_req_wdata,

    input  wire         s_resp_valid,
    input  wire [255:0] s_resp_rdata,
    input  wire         s_resp_ok
);

    // Busy means: we accepted a request and are waiting for its response.
    reg busy;

    // Which client owns the in-flight transaction? 0=A, 1=B.
    reg grant_hold;

    // Round-robin pointer: who to prefer next when both request.
    // 0 => prefer A, 1 => prefer B.
    reg rr_pref;

    // Combinational pick when idle
    wire a_v = a_req_valid;
    wire b_v = b_req_valid;

    wire grant_pick = (a_v && b_v) ? rr_pref : (b_v && !a_v);

    // Only issue to shared reg_if when idle.
    assign s_req_valid = (!busy) && ((grant_pick == 1'b0) ? a_req_valid : b_req_valid);
    assign s_req_write = (grant_pick == 1'b0) ? a_req_write : b_req_write;
    assign s_req_addr  = (grant_pick == 1'b0) ? a_req_addr  : b_req_addr;
    assign s_req_len   = (grant_pick == 1'b0) ? a_req_len   : b_req_len;
    assign s_req_wdata = (grant_pick == 1'b0) ? a_req_wdata : b_req_wdata;

    // Ready is only asserted to the selected client when idle.
    assign a_req_ready = (!busy) && (grant_pick == 1'b0) && s_req_ready;
    assign b_req_ready = (!busy) && (grant_pick == 1'b1) && s_req_ready;

    wire accept = s_req_valid && s_req_ready;

    // Route response based on latched grant_hold.
    assign a_resp_valid = s_resp_valid && (grant_hold == 1'b0);
    assign b_resp_valid = s_resp_valid && (grant_hold == 1'b1);

    assign a_resp_rdata = s_resp_rdata;
    assign b_resp_rdata = s_resp_rdata;

    assign a_resp_ok    = s_resp_ok;
    assign b_resp_ok    = s_resp_ok;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy       <= 1'b0;
            grant_hold <= 1'b0;
            rr_pref    <= 1'b0; // start preferring A
        end else begin
            // Latch grant on accept
            if (accept) begin
                busy       <= 1'b1;
                grant_hold <= grant_pick;
                rr_pref    <= ~grant_pick; // next time prefer the other
            end

            // Release ownership on response
            if (busy && s_resp_valid) begin
                busy <= 1'b0;
            end
        end
    end

endmodule
