// spi_ctrl – generic multi-byte SPI controller
//
// Performs a single SS frame consisting of:
//   1. Write phase: clock out w_len bytes (0..32) from tx_data
//   2. Read phase:  clock out r_len dummy bytes while capturing MISO
//                   into rx_data
//
// Both phases happen under one continuous SS assertion, which is
// exactly how real SPI peripherals (EEPROM, MFRC522, …) expect
// command + data transfers to work.
//
// Two active-low chip-select outputs are provided:
//   cs_sel = 0 → cs0 asserted (MFRC522)
//   cs_sel = 1 → cs1 asserted (EEPROM)
// The unselected line stays high throughout the transfer.
//
// Usage:
//   1. Set tx_data (256-bit = 32 bytes, MSB first: byte 0 is [255:248])
//   2. Set w_len, r_len and cs_sel
//   3. Pulse go
//   4. Wait for done
//   5. Read rx_data (256-bit, byte 0 at [255:248])
//
// If w_len == 0 the write phase is skipped (pure read).
// If r_len == 0 the read  phase is skipped (pure write).

module spi_ctrl (
    input wire clk,
    input wire rst,  // active-low reset

    // ── control ──
    input  wire go,    // pulse to start transfer
    output reg  done,  // pulses when transfer complete
    output reg  busy,  // high during transfer

    // ── transfer lengths ──
    input wire [5:0] w_len,  // number of bytes to write  (0..32)
    input wire [5:0] r_len,  // number of bytes to read   (0..32)

    // ── chip select ──
    input wire cs_sel,  // 0 → MFRC522 (cs0 low) | 1 → EEPROM (cs1 low)

    // ── data ──
    input  wire [255:0] tx_data,  // bytes to send   (byte 0 = [255:248])
    output reg  [255:0] rx_data,  // bytes received  (byte 0 = [255:248])

    // ── SPI bus ──
    output wire sclk,
    output wire mosi,
    input  wire miso,
    output reg  cs0,   // active-low chip select – MFRC522
    output reg  cs1    // active-low chip select – EEPROM
);

  // ── spi_master instance ──
  reg  [7:0] spi_data_in;
  reg        spi_start;
  wire [7:0] spi_data_out;
  wire       spi_done;
  wire       spi_busy;


  // -- retention records --     
  reg go_rec; 
  reg spi_done_rec; 
  reg spi_busy_rec; 

  // Spi clock divisor
  logic spi_clk;
  logic spi_clk_d;  // delayed version for edge detection
  logic spi_clk_en; // one-cycle pulse on rising edge of spi_clk

  clock_divider divider(
      .clk(clk),
      .rst(rst),
      .clk_out(spi_clk)
  );

  // Detect rising edge of spi_clk in the clk domain
  always_ff @(posedge clk) begin
      if (rst)
          spi_clk_d <= 0;
      else
          spi_clk_d <= spi_clk;
  end
  assign spi_clk_en = spi_clk & ~spi_clk_d;

  spi_master u_spi (
      .clk     (clk),
      .clk_en  (spi_clk_en),
      .reset   (rst),
      .data_in (spi_data_in),
      .start   (spi_start),
      .miso    (miso),
      .mosi    (mosi),
      .sclk    (sclk),
      .data_out(spi_data_out),
      .done    (spi_done),
      .busy    (spi_busy)
  );

  // ── latched transfer config ──
  reg [5:0] w_cnt;  // TX bytes remaining
  reg [5:0] r_cnt;  // RX bytes remaining
  reg [7:0] byte_idx;  // current byte index
  reg       cs_sel_r;  // latched chip-select choice

  // ── state machine ──
  localparam S_IDLE = 3'd0, S_SS_ON = 3'd1,  // assert selected CS, load first byte
  S_START = 3'd2,  // pulse spi_start
  S_WAIT = 3'd3,  // wait for spi_done
  S_DONE = 3'd4;

  reg [2:0] state;

  always @(posedge clk) begin
    if (rst) begin
      state        <= S_IDLE;
      spi_data_in  <= 8'd0;
      spi_start    <= 1'b0;
      cs0          <= 1'b1;
      cs1          <= 1'b1;
      cs_sel_r     <= 1'b0;
      done         <= 1'b0;
      busy         <= 1'b0;
      w_cnt        <= 6'd0;
      r_cnt        <= 6'd0;
      byte_idx     <= 8'd0;
      rx_data      <= 256'd0;
      go_rec       <= 1'b0;
      spi_done_rec <= 1'b0;
      spi_busy_rec <= 1'b0;
    end else begin
      done      <= 1'b0;
      if (go)
        go_rec <= go; 
      else if (spi_clk_en)
        go_rec <= 1'b0;

      if (spi_done)
        spi_done_rec <= spi_done;
      else if (spi_clk_en)
        spi_done_rec <= 1'b0;

      if (spi_busy)
        spi_busy_rec <= spi_busy;
      else if (spi_clk_en)
        spi_busy_rec <= 1'b0;

      if (spi_clk_en) begin
        spi_start <= 1'b0;

        case (state)
          S_IDLE: begin
            if (go_rec && (w_len != 0 || r_len != 0)) begin
              busy     <= 1'b1;
              w_cnt    <= w_len;
              r_cnt    <= r_len;
              byte_idx <= 8'd0;
              cs_sel_r <= cs_sel;  // latch selection at start
              state    <= S_SS_ON;
            end
          end

          // Assert selected CS and load the first byte
          S_SS_ON: begin
            if (cs_sel_r == 1'b0) cs0 <= 1'b0;  // select MFRC522
            else cs1 <= 1'b0;  // select EEPROM

            if (w_cnt != 0) spi_data_in <= tx_data[255 -: 8];
            else spi_data_in <= 8'h00;
            state <= S_START;
          end

          // Pulse spi_start
          S_START: begin
            spi_start <= 1'b1;
            if (spi_busy_rec)
              state <= S_WAIT;
          end

          // Wait for byte to finish, then decide what's next
          S_WAIT: begin
            if (spi_done_rec) begin
              if (w_cnt != 0) begin
                // ── write phase ──
                w_cnt <= w_cnt - 1;
                if (w_cnt == 1) begin
                  if (r_cnt != 0) begin
                    byte_idx    <= 8'd0;
                    spi_data_in <= 8'h00;
                    state       <= S_START;
                  end else begin
                    state <= S_DONE;
                  end
                end else begin
                  byte_idx    <= byte_idx + 1;
                  spi_data_in <= tx_data[255 - (byte_idx + 8'd1)*8 -: 8];
                  state       <= S_START;
                end
              end else begin
                // ── read phase ──
                rx_data[255-byte_idx*8-:8] <= spi_data_out;
                r_cnt <= r_cnt - 1;
                if (r_cnt == 1) begin
                  state <= S_DONE;
                end else begin
                  byte_idx    <= byte_idx + 1;
                  spi_data_in <= 8'h00;
                  state       <= S_START;
                end
              end
            end
          end

          // Deassert both CS lines, signal completion
          S_DONE: begin
            cs0   <= 1'b1;
            cs1   <= 1'b1;
            done  <= 1'b1;
            busy  <= 1'b0;
            state <= S_IDLE;
          end

          default: state <= S_IDLE;
        endcase
      end
  end
end

endmodule

