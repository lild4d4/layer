// spi_arb – round-robin arbiter for SPI clients (EEPROM, MFRC)
//
// Two clients share a single spi_ctrl instance.
// Client A → EEPROM (cs_sel=1, cs1), Client B → MFRC (cs_sel=0, cs0)
//
// Client interface mimics spi_ctrl: go/wlen/rlen/tx_data → done/rx_data/busy
// Round-robin arbitration when both clients request simultaneously.
//
// Clients may pulse go for a single cycle. If the bus is busy (or the other
// client wins arbitration), the request is latched as "pending" and will be
// served once the current transaction completes. At most one pending request
// per client is stored.

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
  wire [255:0] ctrl_rx_data;

  // --- Held transaction data (stable for entire SPI transaction) ---
  reg  [  5:0] held_wlen;
  reg  [  5:0] held_rlen;
  reg  [255:0] held_tx_data;
  reg          held_cs_sel;

  // --- Arbitration state ---
  reg          busy;
  reg          grant_hold;
  reg          rr_pref;

  // --- Pending request latches ---
  reg          a_pending;
  reg  [  5:0] a_pending_wlen;
  reg  [  5:0] a_pending_rlen;
  reg  [255:0] a_pending_tx_data;

  reg          b_pending;
  reg  [  5:0] b_pending_wlen;
  reg  [  5:0] b_pending_rlen;
  reg  [255:0] b_pending_tx_data;

  // --- Effective request signals (live OR pending) ---
  wire         a_req = a_go | a_pending;
  wire         b_req = b_go | b_pending;

  // --- Combinational arbitration ---
  wire         grant_pick = (a_req && b_req) ? rr_pref : (b_req && !a_req);

  // --- Effective data: prefer live go over pending ---
  wire [  5:0] a_eff_wlen = a_go ? a_wlen : a_pending_wlen;
  wire [  5:0] a_eff_rlen = a_go ? a_rlen : a_pending_rlen;
  wire [255:0] a_eff_tx_data = a_go ? a_tx_data : a_pending_tx_data;

  wire [  5:0] b_eff_wlen = b_go ? b_wlen : b_pending_wlen;
  wire [  5:0] b_eff_rlen = b_go ? b_rlen : b_pending_rlen;
  wire [255:0] b_eff_tx_data = b_go ? b_tx_data : b_pending_tx_data;

  // --- Winner's data for this grant cycle ---
  wire [  5:0] win_wlen = (grant_pick == 1'b0) ? a_eff_wlen : b_eff_wlen;
  wire [  5:0] win_rlen = (grant_pick == 1'b0) ? a_eff_rlen : b_eff_rlen;
  wire [255:0] win_tx_data = (grant_pick == 1'b0) ? a_eff_tx_data : b_eff_tx_data;
  wire         win_cs_sel = (grant_pick == 1'b0) ? 1'b1 : 1'b0;

  // --- ctrl_go fires for one cycle to start a new transaction ---
  assign ctrl_go = (!busy) && (a_req || b_req);

  // --- Route held data to spi_ctrl (stable for entire transaction) ---
  // On the grant cycle, combinational pass-through of winner's data;
  // after that, the held registers keep it stable.
  wire [  5:0] ctrl_wlen = ctrl_go ? win_wlen : held_wlen;
  wire [  5:0] ctrl_rlen = ctrl_go ? win_rlen : held_rlen;
  wire [255:0] ctrl_tx_data = ctrl_go ? win_tx_data : held_tx_data;
  wire         ctrl_cs_sel = ctrl_go ? win_cs_sel : held_cs_sel;

  // --- Busy to clients ---
  assign a_busy    = busy && (grant_hold == 1'b0);
  assign b_busy    = busy && (grant_hold == 1'b1);

  // --- Response routing ---
  assign a_done    = ctrl_done && (grant_hold == 1'b0);
  assign b_done    = ctrl_done && (grant_hold == 1'b1);
  assign a_rx_data = ctrl_rx_data;
  assign b_rx_data = ctrl_rx_data;

  // --- State update ---
  always @(posedge clk) begin
    if (rst) begin
      busy              <= 1'b0;
      grant_hold        <= 1'b0;
      rr_pref           <= 1'b0;
      held_wlen         <= 6'd0;
      held_rlen         <= 6'd0;
      held_tx_data      <= 256'd0;
      held_cs_sel       <= 1'b0;
      a_pending         <= 1'b0;
      a_pending_wlen    <= 6'd0;
      a_pending_rlen    <= 6'd0;
      a_pending_tx_data <= 256'd0;
      b_pending         <= 1'b0;
      b_pending_wlen    <= 6'd0;
      b_pending_rlen    <= 6'd0;
      b_pending_tx_data <= 256'd0;
    end else begin

      // --- Latch pending requests ---
      // A: latch if go arrives but we can't serve it now
      if (a_go && (busy || (ctrl_go && grant_pick != 1'b0))) begin
        a_pending         <= 1'b1;
        a_pending_wlen    <= a_wlen;
        a_pending_rlen    <= a_rlen;
        a_pending_tx_data <= a_tx_data;
      end else if (a_pending && ctrl_go && !busy && grant_pick == 1'b0) begin
        a_pending <= 1'b0;
      end

      // B: latch if go arrives but we can't serve it now
      if (b_go && (busy || (ctrl_go && grant_pick != 1'b1))) begin
        b_pending         <= 1'b1;
        b_pending_wlen    <= b_wlen;
        b_pending_rlen    <= b_rlen;
        b_pending_tx_data <= b_tx_data;
      end else if (b_pending && ctrl_go && !busy && grant_pick == 1'b1) begin
        b_pending <= 1'b0;
      end

      // --- Grant: latch winner's data and mark busy ---
      if (ctrl_go && !ctrl_busy) begin
        busy         <= 1'b1;
        grant_hold   <= grant_pick;
        rr_pref      <= ~grant_pick;
        held_wlen    <= win_wlen;
        held_rlen    <= win_rlen;
        held_tx_data <= win_tx_data;
        held_cs_sel  <= win_cs_sel;
      end

      // --- Transaction complete ---
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



