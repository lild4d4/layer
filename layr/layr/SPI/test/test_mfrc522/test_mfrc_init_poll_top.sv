// test_mfrc_init_poll_top – testbench wrapper
//
// Instantiates mfrc_init_poll → spi_arb → spi_ctrl → spi_master
// Exposes the command interface and SPI bus signals to cocotb.

module test_mfrc_init_poll_top (
    input wire clk,
    input wire rst,

    // ── command inputs ──
    input  wire       cmd_init,
    input  wire       cmd_poll,

    // ── status outputs ──
    output wire        ready,
    output wire        init_done,
    output wire        card_present,
    output wire [15:0] atqa,
    output wire [ 7:0] status,

    // ── SPI bus (directly accessible by cocotb slave) ──
    output wire sclk,
    output wire mosi,
    input  wire miso,
    output wire cs0,
    output wire cs1
);

  // Wires between modules
  wire         b_go;
  wire         b_done;
  wire         b_busy;
  wire [255:0] b_tx_data;
  wire [255:0] b_rx_data;
  wire [ 5:0] b_w_len;
  wire [ 5:0] b_r_len;

  // SPI arbiter signals
  wire         ctrl_go;
  wire         ctrl_done;
  wire         ctrl_busy;
  wire [255:0] ctrl_tx_data;
  wire [255:0] ctrl_rx_data;
  wire [ 5:0] ctrl_w_len;
  wire [ 5:0] ctrl_r_len;
  wire         ctrl_cs_sel;

  // Instantiate mfrc_init_poll (connects to spi_arb client B)
  mfrc_init_poll u_mfrc_init_poll (
      .clk(clk),
      .rst(rst),

      .cmd_init(cmd_init),
      .cmd_poll(cmd_poll),

      .ready(ready),
      .init_done(init_done),
      .card_present(card_present),
      .atqa(atqa),
      .status(status),

      .spi_go(b_go),
      .spi_done(b_done),
      .spi_busy(b_busy),
      .spi_tx_data(b_tx_data),
      .spi_w_len(b_w_len),
      .spi_r_len(b_r_len)
  );

  // Instantiate spi_arb (client B = MFRC, cs_sel=0 = cs0)
  spi_arb u_spi_arb (
      .clk(clk),
      .rst(rst),

      // Client A (EEPROM) - not used
      .a_go(1'b0),
      .a_wlen(6'd0),
      .a_rlen(6'd0),
      .a_tx_data(256'd0),
      .a_done(),
      .a_rx_data(),
      .a_busy(),

      // Client B (MFRC522)
      .b_go(b_go),
      .b_wlen(b_w_len),
      .b_rlen(b_r_len),
      .b_tx_data(b_tx_data),
      .b_done(b_done),
      .b_rx_data(b_rx_data),
      .b_busy(b_busy),

      .sclk(sclk),
      .mosi(mosi),
      .miso(miso),
      .cs0(cs0),
      .cs1(cs1)
  );

  // Internal spi_ctrl instance (inside spi_arb)
  spi_ctrl u_spi_ctrl (
      .clk(clk),
      .rst(rst),

      .go(ctrl_go),
      .done(ctrl_done),
      .busy(ctrl_busy),
      .w_len(ctrl_w_len),
      .r_len(ctrl_r_len),
      .cs_sel(ctrl_cs_sel),
      .tx_data(ctrl_tx_data),
      .rx_data(ctrl_rx_data),

      .sclk(sclk),
      .mosi(mosi),
      .miso(miso),
      .cs0(cs0),
      .cs1(cs1)
  );

endmodule
