
module mfrc_top (
    input wire clk,
    input wire rst,

    // mfrc_core transceive API
    input  wire         trx_valid,
    output wire         trx_ready,
    input  wire [  4:0] trx_tx_len,
    input  wire [255:0] trx_tx_data,
    input  wire [  2:0] trx_tx_last_bits,
    input  wire [ 31:0] trx_timeout_cycles,

    output wire         trx_done,
    output wire         trx_ok,
    output wire [  4:0] trx_rx_len,
    output wire [255:0] trx_rx_data,
    output wire [  2:0] trx_rx_last_bits,
    output wire [  7:0] trx_error,

    // connection to spi_arb
    output wire         spi_go,
    input  wire         spi_done,
    input  wire         spi_busy,
    output wire [  5:0] spi_w_len,
    output wire [  5:0] spi_r_len,
    output wire [255:0] spi_tx_data,
    input  wire [255:0] spi_rx_data
);

  // -------- mfrc_core <-> mfrc_reg_if shared wires --------
  wire s_req_valid, s_req_ready, s_req_write;
  wire [ 5:0] s_req_addr;
  wire [ 4:0] s_req_len;
  wire [255:0] s_req_wdata;

  wire s_resp_valid, s_resp_ok;
  wire [255:0] s_resp_rdata;

  mfrc_core u_mfrc_core (
      .clk(clk),
      .rst(rst),

      .trx_valid(trx_valid),
      .trx_ready(trx_ready),
      .trx_tx_len(trx_tx_len),
      .trx_tx_data(trx_tx_data),
      .trx_tx_last_bits(trx_tx_last_bits),
      .trx_timeout_cycles(trx_timeout_cycles),

      .trx_done(trx_done),
      .trx_ok(trx_ok),
      .trx_rx_len(trx_rx_len),
      .trx_rx_data(trx_rx_data),
      .trx_rx_last_bits(trx_rx_last_bits),
      .trx_error(trx_error),

      .reg_req_valid(s_req_valid),
      .reg_req_ready(s_req_ready),
      .reg_req_write(s_req_write),
      .reg_req_addr (s_req_addr),
      .reg_req_len  (s_req_len),
      .reg_req_wdata(s_req_wdata),

      .reg_resp_valid(s_resp_valid),
      .reg_resp_rdata(s_resp_rdata),
      .reg_resp_ok   (s_resp_ok)
  );

  mfrc_reg_if u_reg_if (
      .clk(clk),
      .rst(rst),

      .req_valid(s_req_valid),
      .req_ready(s_req_ready),
      .req_write(s_req_write),
      .req_addr (s_req_addr),
      .req_len  (s_req_len),
      .req_wdata(s_req_wdata),

      .resp_valid(s_resp_valid),
      .resp_rdata(s_resp_rdata),
      .resp_ok   (s_resp_ok),

      .spi_go(spi_go),
      .spi_done(spi_done),
      .spi_busy(spi_busy),
      .spi_w_len(spi_w_len),
      .spi_r_len(spi_r_len),
      .spi_tx_data(spi_tx_data),
      .spi_rx_data(spi_rx_data)
  );

endmodule
