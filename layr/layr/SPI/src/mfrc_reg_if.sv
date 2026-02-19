// mfrc_reg_if – MFRC522 register-level SPI interface
//
// Translates register read/write requests into SPI bus transactions
// via the shared spi_ctrl interface (through spi_arb).
//
// MFRC522 SPI protocol (datasheet §8.1.2):
//   Write: addr_byte(bit7=0, bits[6:1]=addr, bit0=0), then data byte(s)
//   Read:  addr_byte(bit7=1, bits[6:1]=addr, bit0=0), then clock out data
//
// Because spi_ctrl only captures MISO during its "read phase" (not during
// the "write phase"), each register read is a 2-byte SPI transaction:
//   w_len=1 (address byte), r_len=1 (dummy byte -> captures data).
//
// Burst reads (req_len > 0) are performed by iterating: the state machine
// issues individual 2-byte reads and aggregates results.  This matches the
// Arduino reference implementation which reads one register at a time.
//
// Burst writes use a single SPI transaction:
//   w_len = 1 + N (address byte + N data bytes), r_len = 0.

module mfrc_reg_if (
    input wire clk,
    input wire rst,

    // -- request interface --
    input  wire         req_valid,   // pulse to start a request
    output reg          req_ready,   // high when idle
    input  wire         req_write,   // 1 = write, 0 = read
    input  wire [  5:0] req_addr,    // 6-bit register address
    input  wire [  4:0] req_len,     // number of bytes - 1 (0 = 1 byte)
    input  wire [255:0] req_wdata,   // write data (byte 0 = [255:248])

    // -- response interface --
    output reg          resp_valid,  // pulses when transfer complete
    output reg  [255:0] resp_rdata,  // read data (byte 0 = [255:248])
    output reg          resp_ok,     // always 1 (no error detection yet)

    // -- spi_ctrl / spi_arb interface --
    output reg          spi_go,
    input  wire         spi_done,
    input  wire         spi_busy,
    output reg  [  5:0] spi_w_len,
    output reg  [  5:0] spi_r_len,
    output reg  [255:0] spi_tx_data,
    input  wire [255:0] spi_rx_data
);

  // -- state machine --
  localparam [2:0] S_IDLE    = 3'd0,
                   S_SUBMIT  = 3'd1,
                   S_WAIT    = 3'd2,
                   S_RD_NEXT = 3'd3,
                   S_DONE    = 3'd4;

  (* MARK_DEBUG = "TRUE" *) reg [2:0] state;

  // Latched request parameters
  reg        lat_write;
  reg [5:0]  lat_addr;
  reg [4:0]  lat_len;     // total bytes - 1
  reg [4:0]  byte_idx;    // current byte index for burst reads
  reg [255:0] lat_wdata;  // latched write data

  // Total byte count
  wire [5:0] byte_count = {1'b0, lat_len} + 6'd1;

  // Helper: SPI address byte for MFRC522
  wire [7:0] addr_byte_wr = {1'b0, lat_addr, 1'b0};
  wire [7:0] addr_byte_rd = {1'b1, lat_addr, 1'b0};

  integer i;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state       <= S_IDLE;
      req_ready   <= 1'b1;
      resp_valid  <= 1'b0;
      resp_rdata  <= 256'd0;
      resp_ok     <= 1'b0;
      spi_go      <= 1'b0;
      spi_w_len   <= 6'd0;
      spi_r_len   <= 6'd0;
      spi_tx_data <= 256'd0;
      lat_write   <= 1'b0;
      lat_addr    <= 6'd0;
      lat_len     <= 5'd0;
      lat_wdata   <= 256'd0;
      byte_idx    <= 5'd0;
    end else begin
      resp_valid <= 1'b0;
      spi_go     <= 1'b0;

      case (state)
        // ------------------------------------------------
        S_IDLE: begin
          if (req_valid && req_ready) begin
            lat_write  <= req_write;
            lat_addr   <= req_addr;
            lat_len    <= req_len;
            lat_wdata  <= req_wdata;
            byte_idx   <= 5'd0;
            resp_rdata <= 256'd0;
            req_ready  <= 1'b0;
            state      <= S_SUBMIT;
          end
        end

        // ------------------------------------------------
        S_SUBMIT: begin
          if (!spi_busy) begin
            spi_tx_data <= 256'd0;

            if (lat_write) begin
              // -- WRITE: single SPI transaction --
              // [addr_byte_wr] [data_0] [data_1] ...
              spi_w_len <= byte_count + 6'd1;
              spi_r_len <= 6'd0;

              spi_tx_data[255:248] <= addr_byte_wr;
              for (i = 0; i < 32; i = i + 1) begin
                if (i[4:0] <= lat_len)
                  spi_tx_data[247 - i*8 -: 8] <= lat_wdata[255 - i*8 -: 8];
              end

            end else begin
              // -- READ: one 2-byte transaction per byte --
              // w_len=1 (addr byte), r_len=1 (clocks out data)
              spi_w_len <= 6'd1;
              spi_r_len <= 6'd1;
              spi_tx_data[255:248] <= addr_byte_rd;
            end

            spi_go <= 1'b1;
            state  <= S_WAIT;
          end
        end

        // ------------------------------------------------
        S_WAIT: begin
          if (spi_done) begin
            if (lat_write) begin
              // Write complete
              resp_ok    <= 1'b1;
              resp_valid <= 1'b1;
              state      <= S_DONE;
            end else begin
              // Capture read byte into result at position [byte_idx]
              resp_rdata[255 - byte_idx*8 -: 8] <= spi_rx_data[255:248];

              if (byte_idx == lat_len) begin
                // All bytes read
                resp_ok    <= 1'b1;
                resp_valid <= 1'b1;
                state      <= S_DONE;
              end else begin
                // More bytes to read
                byte_idx <= byte_idx + 5'd1;
                state    <= S_RD_NEXT;
              end
            end
          end
        end

        // ------------------------------------------------
        // Issue next single-byte read
        S_RD_NEXT: begin
          if (!spi_busy) begin
            spi_tx_data <= 256'd0;
            spi_w_len   <= 6'd1;
            spi_r_len   <= 6'd1;
            spi_tx_data[255:248] <= addr_byte_rd;
            spi_go <= 1'b1;
            state  <= S_WAIT;
          end
        end

        // ------------------------------------------------
        S_DONE: begin
          req_ready <= 1'b1;
          state     <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
