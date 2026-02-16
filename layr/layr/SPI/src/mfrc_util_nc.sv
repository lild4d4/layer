// mfrc_util – small MFRC522 utility client
//
// For now: read VersionReg (0x37) through a shared mfrc_reg_if interface.
//
// Interface style mirrors mfrc_core:
//   - start/ready handshake
//   - done pulse with version byte

module mfrc_util (
    input wire clk,
    input wire rst,

    // Command
    input  wire ver_valid,
    output wire ver_ready,

    // Result
    output reg       ver_done,
    output reg       ver_ok,
    output reg [7:0] ver_value,

    // Shared mfrc_reg_if request/response interface (to arbiter)
    output reg          reg_req_valid,
    input  wire         reg_req_ready,
    output reg          reg_req_write,
    output reg  [  5:0] reg_req_addr,
    output reg  [  4:0] reg_req_len,
    output reg  [255:0] reg_req_wdata,

    input wire         reg_resp_valid,
    input wire [255:0] reg_resp_rdata,
    input wire         reg_resp_ok
);

  // MFRC522 VersionReg address (6-bit)
  localparam [5:0] REG_VERSION = 6'h37;

  localparam [1:0] S_IDLE = 2'd0, S_ISSUE = 2'd1, S_WAIT = 2'd2, S_DONE = 2'd3;

  reg [1:0] state;

  assign ver_ready = (state == S_IDLE);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state         <= S_IDLE;
      ver_done      <= 1'b0;
      ver_ok        <= 1'b0;
      ver_value     <= 8'd0;

      reg_req_valid <= 1'b0;
      reg_req_write <= 1'b0;
      reg_req_addr  <= 6'd0;
      reg_req_len   <= 5'd0;
      reg_req_wdata <= 256'd0;
    end else begin
      // defaults
      ver_done      <= 1'b0;
      reg_req_valid <= 1'b0;

      case (state)
        S_IDLE: begin
          if (ver_valid) begin
            state <= S_ISSUE;
          end
        end

        S_ISSUE: begin
          if (reg_req_ready) begin
            // 1-byte register read
            reg_req_valid <= 1'b1;
            reg_req_write <= 1'b0;
            reg_req_addr  <= REG_VERSION;
            reg_req_len   <= 5'd0;  // 0 => 1 byte
            reg_req_wdata <= 256'd0;
            state         <= S_WAIT;
          end
        end

        S_WAIT: begin
          if (reg_resp_valid) begin
            ver_value <= reg_resp_rdata[255:248];
            ver_ok    <= reg_resp_ok;
            state     <= S_DONE;
          end
        end

        S_DONE: begin
          ver_done <= 1'b1;
          state    <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
