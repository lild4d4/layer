// spi_arb – round-robin arbiter for SPI clients (EEPROM, MFRC)
//
// Two clients share a single spi_ctrl instance.
// Client A → EEPROM (cs_sel=1, cs1), Client B → MFRC (cs_sel=0, cs0)
//
// Client interface mimics spi_ctrl: go/wlen/rlen/tx_data → done/rx_data/busy
// Round-robin arbitration when both clients request simultaneously.

module spi_arb (
    input wire clk,
    input wire rst,

    // Client A (EEPROM)
    input  wire         a_go,
    input  wire [  5:0] a_wlen,
    input  wire [  5:0] a_rlen,
    input  wire [255:0] a_tx_data,
    output wire         a_done,
    output wire [255:0] a_rx_data,
    output wire         a_busy,

    // Client B (MFRC)
    input  wire         b_go,
    input  wire [  5:0] b_wlen,
    input  wire [  5:0] b_rlen,
    input  wire [255:0] b_tx_data,
    output wire         b_done,
    output wire [255:0] b_rx_data,
    output wire         b_busy,

    // SPI pins (from internal spi_ctrl)
    output wire sclk,
    output wire mosi,
    input  wire miso,
    output wire cs0,
    output wire cs1
);

  // --- Internal spi_ctrl signals ---
  wire         ctrl_go;
  wire         ctrl_done;
  wire         ctrl_busy;
  wire [  5:0] ctrl_wlen;
  wire [  5:0] ctrl_rlen;
  wire [255:0] ctrl_tx_data;
  wire         ctrl_cs_sel;
  wire [255:0] ctrl_rx_data;

  // --- Arbitration state ---
  reg          busy;
  reg          grant_hold;
  reg          rr_pref;

  // --- Combinational arbitration ---
  wire         a_v = a_go;
  wire         b_v = b_go;
  wire         grant_pick = (a_v && b_v) ? rr_pref : (b_v && !a_v);

  // Route selected client to spi_ctrl
  wire         mux_sel = busy ? grant_hold : grant_pick;

  assign ctrl_go      = (!busy) && ((grant_pick == 1'b0) ? a_go : b_go);
  assign ctrl_wlen    = (mux_sel == 1'b0) ? a_wlen : b_wlen;
  assign ctrl_rlen    = (mux_sel == 1'b0) ? a_rlen : b_rlen;
  assign ctrl_tx_data = (mux_sel == 1'b0) ? a_tx_data : b_tx_data;
  assign ctrl_cs_sel  = (mux_sel == 1'b0) ? 1'b1 : 1'b0;

  // --- Busy to clients ---
  assign a_busy       = busy && (grant_hold == 1'b0);
  assign b_busy       = busy && (grant_hold == 1'b1);

  // --- Response routing ---
  assign a_done       = ctrl_done && (grant_hold == 1'b0);
  assign b_done       = ctrl_done && (grant_hold == 1'b1);
  assign a_rx_data    = ctrl_rx_data;
  assign b_rx_data    = ctrl_rx_data;

  // --- State update ---
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      busy       <= 1'b0;
      grant_hold <= 1'b0;
      rr_pref    <= 1'b0;
    end else begin
      if (ctrl_go && !ctrl_busy) begin
        busy       <= 1'b1;
        grant_hold <= grant_pick;
        rr_pref    <= ~grant_pick;
      end

      if (busy && ctrl_done) begin
        busy <= 1'b0;
      end
    end
  end

  // --- Internal spi_ctrl instance ---
  spi_ctrl u_spi_ctrl (
      .clk    (clk),
      .rst    (rst),
      .go     (ctrl_go),
      .done   (ctrl_done),
      .busy   (ctrl_busy),
      .w_len  (ctrl_wlen),
      .r_len  (ctrl_rlen),
      .cs_sel (ctrl_cs_sel),
      .tx_data(ctrl_tx_data),
      .rx_data(ctrl_rx_data),
      .sclk   (sclk),
      .mosi   (mosi),
      .miso   (miso),
      .cs0    (cs0),
      .cs1    (cs1)
  );

endmodule
