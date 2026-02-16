// mfrc_reg_if – MFRC522 register-access layer on top of spi_ctrl
//
// Translates simple register read/write requests into SPI transactions
// that follow the MFRC522 SPI framing rules:
//
//   Address byte: { R/W, addr[5:0], 0 }
//     bit7 = 1 for READ, 0 for WRITE
//     bits[6:1] = 6-bit register address
//     bit0 = 0
//
//   Write: addr_byte + N data bytes  → spi_ctrl w_len = 1+N, r_len = 0
//   Read:  addr_byte + N dummy bytes → spi_ctrl w_len = 1,   r_len = N
//
// Supports burst access (req_len = 1..32) for registers like FIFODataReg.
// One request at a time (no pipelining).

module mfrc_reg_if (
    input wire clk,
    input wire rst,

    // ── request side ──
    input  wire         req_valid,  // pulse to submit request
    output wire         req_ready,  // high when idle, can accept
    input  wire         req_write,  // 1 = write, 0 = read
    input  wire [  5:0] req_addr,   // MFRC522 register address
    input  wire [  4:0] req_len,    // number of data bytes 0 -> 1 
    input  wire [255:0] req_wdata,  // write payload (byte0 at [255:248])

    // ── response side ──
    output reg         resp_valid,  // 1-cycle pulse when done
    output reg [255:0] resp_rdata,  // read payload (byte0 at [255:248])
    output reg         resp_ok,     // always 1 for now

    // ── connection to spi_ctrl ──
    output reg          spi_go,
    input  wire         spi_done,
    input  wire         spi_busy,
    output reg  [  5:0] spi_w_len,
    output reg  [  5:0] spi_r_len,
    output reg  [255:0] spi_tx_data,
    input  wire [255:0] spi_rx_data
);
  // ── FSM ──
  localparam S_IDLE = 2'd0, S_ISSUE = 2'd1, S_WAIT = 2'd2, S_RESP = 2'd3;

  reg [  1:0] state;

  // Latched request fields
  reg         lat_write;
  reg [  5:0] lat_addr;
  reg [  4:0] lat_len;
  reg [255:0] lat_wdata;

  assign req_ready = (state == S_IDLE);

  // Build MFRC522 address byte
  // Read:  { 1, addr[5:0], 0 }
  // Write: { 0, addr[5:0], 0 }
  function [7:0] addr_byte(input write, input [5:0] addr);
    addr_byte = {write ? 1'b0 : 1'b1, addr, 1'b0};
  endfunction

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state       <= S_IDLE;
      lat_write   <= 1'b0;
      lat_addr    <= 6'd0;
      lat_len     <= 5'd1;
      lat_wdata   <= 256'd0;
      spi_go      <= 1'b0;
      spi_w_len   <= 6'd0;
      spi_r_len   <= 6'd0;
      spi_tx_data <= 256'd0;
      resp_valid  <= 1'b0;
      resp_rdata  <= 256'd0;
      resp_ok     <= 1'b0;
    end else begin
      // Defaults
      spi_go     <= 1'b0;
      resp_valid <= 1'b0;

      case (state)
        // ─────────────────────────────────────
        S_IDLE: begin
          if (req_valid) begin
            lat_write <= req_write;
            lat_addr  <= req_addr;
            lat_len   <= req_len;
            lat_wdata <= req_wdata;
            state     <= S_ISSUE;
          end
        end

        // Build spi_ctrl inputs and pulse go
        S_ISSUE: begin
          if (lat_write) begin
            // Write: addr_byte + lat_len data bytes
            spi_w_len <= 6'd2 + lat_len;
            spi_r_len <= 6'd0;

            // Byte 0 = addr_byte
            spi_tx_data[255:248] <= addr_byte(1'b1, lat_addr);
            // Bytes 1..N = write data from lat_wdata[255:248], [247:240], ...
            // Shift lat_wdata left by 8 bits (make room for addr byte at MSB)
            spi_tx_data[247:0] <= lat_wdata[255:8];
          end else begin
            // Read: addr_byte only, then r_len dummy bytes
            spi_w_len <= 6'd1;
            spi_r_len <= lat_len + 6'd1;

            spi_tx_data[255:248] <= addr_byte(1'b0, lat_addr);
            spi_tx_data[247:0] <= 248'd0;  // don't care
          end

          spi_go <= 1'b1;
          state  <= S_WAIT;
        end

        // Wait for spi_ctrl to finish
        S_WAIT: begin
          if (spi_done) begin
            // For reads: spi_rx_data byte0 is first read byte
            resp_rdata <= spi_rx_data;
            resp_ok    <= 1'b1;
            state      <= S_RESP;
          end
        end

        // Pulse resp_valid for one cycle
        S_RESP: begin
          resp_valid <= 1'b1;
          state      <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
