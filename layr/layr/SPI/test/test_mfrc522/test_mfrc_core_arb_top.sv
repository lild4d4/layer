// test_mfrc_core_arb_top – testbench wrapper for mfrc_top (with arbiter)
//
// Instantiates spi_top and spi_ctrl side by side, wiring the spi_*
// ports between them so the cocotb test can attach an SPI slave mock
// to the physical bus signals.

module test_mfrc_core_arb_top (
    input wire clk,
    input wire rst,

    // ── Transceive request ──
    input  wire         trx_valid,
    output wire         trx_ready,
    input  wire [  4:0] trx_tx_len,
    input  wire [255:0] trx_tx_data,
    input  wire [  2:0] trx_tx_last_bits,
    input  wire [ 31:0] trx_timeout_cycles,

    // ── Transceive response ──
    output wire         trx_done,
    output wire         trx_ok,
    output wire [  4:0] trx_rx_len,
    output wire [255:0] trx_rx_data,
    output wire [  2:0] trx_rx_last_bits,
    output wire [  7:0] trx_error,

    // ── SPI bus (directly exposed for cocotb mock) ──
    output wire sclk,
    output wire mosi,
    input  wire miso,
    output wire cs0,
    output wire cs1
);

  // spi_top <-> spi_ctrl wires
  wire         spi_go;
  wire         spi_done;
  wire         spi_busy;
  wire [  5:0] spi_w_len;
  wire [  5:0] spi_r_len;
  wire [255:0] spi_tx_data;
  wire [255:0] spi_rx_data;

  // util API – unused in this test; tie off ver_valid
  wire         ver_ready;
  wire         ver_done;
  wire         ver_ok;
  wire [  7:0] ver_value;

  mfrc_top u_mfrc_top (
      .clk(clk),
      .rst(rst),

      .trx_valid         (trx_valid),
      .trx_ready         (trx_ready),
      .trx_tx_len        (trx_tx_len),
      .trx_tx_data       (trx_tx_data),
      .trx_tx_last_bits  (trx_tx_last_bits),
      .trx_timeout_cycles(trx_timeout_cycles),

      .trx_done        (trx_done),
      .trx_ok          (trx_ok),
      .trx_rx_len      (trx_rx_len),
      .trx_rx_data     (trx_rx_data),
      .trx_rx_last_bits(trx_rx_last_bits),
      .trx_error       (trx_error),

      .ver_valid(1'b0),
      .ver_ready(ver_ready),
      .ver_done (ver_done),
      .ver_ok   (ver_ok),
      .ver_value(ver_value),

      .spi_go     (spi_go),
      .spi_done   (spi_done),
      .spi_busy   (spi_busy),
      .spi_w_len  (spi_w_len),
      .spi_r_len  (spi_r_len),
      .spi_tx_data(spi_tx_data),
      .spi_rx_data(spi_rx_data)
  );

  spi_ctrl u_spi_ctrl (
      .clk(clk),
      .rst(rst),

      .go     (spi_go),
      .done   (spi_done),
      .busy   (spi_busy),
      .w_len  (spi_w_len),
      .r_len  (spi_r_len),
      .tx_data(spi_tx_data),
      .rx_data(spi_rx_data),
      .cs_sel (1'b0),

      .sclk(sclk),
      .mosi(mosi),
      .miso(miso),
      .cs0 (cs0),
      .cs1 (cs1)
  );

endmodule
