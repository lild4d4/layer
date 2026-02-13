// spi_multibyte_echo – sends 16 bytes through spi_master in a single
// SS frame, then performs a second 16-byte SS frame to read back
// the slave's reply.
//
// This is how real SPI peripherals work: multi-byte commands and
// data are transferred under a single SS assertion.
//
// The external test-bench slave captures the 16 TX bytes, increments
// each by 1, and sends them back during the RX frame.

module spi_multibyte_echo (
    input  wire        clk,
    input  wire        rst_n,       // active-low reset

    // Control interface
    input  wire        go,          // pulse high for 1 clk to start
    output reg         done,        // pulses high for 1 clk when complete
    output reg         busy,        // high while sequence is in progress

    // RX data – read by testbench after done
    input  wire [3:0]  rx_addr,     // address 0..15
    output wire [7:0]  rx_data,     // rx_buf[rx_addr]

    // SPI bus
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,
    output reg         ss
);

    // ── TX and RX buffers ──
    reg [7:0] tx_buf [0:15];
    reg [7:0] rx_buf [0:15];

    assign rx_data = rx_buf[rx_addr];

    // ── Initialize TX buffer with a deterministic pattern ──
    integer k;
    integer i;
    initial begin
        for (k = 0; k < 16; k = k + 1)
            tx_buf[k] = (k + 10) & 8'hFF;
    end

    // ── spi_master instance ──
    reg  [7:0] spi_data_in;
    reg        spi_start;
    wire [7:0] spi_data_out;
    wire       spi_done;
    wire       spi_busy;

    spi_master u_spi (
        .clk      (clk),
        .reset    (~rst_n),
        .data_in  (spi_data_in),
        .start    (spi_start),
        .miso     (miso),
        .mosi     (mosi),
        .sclk     (sclk),
        .data_out (spi_data_out),
        .done     (spi_done),
        .busy     (spi_busy)
    );

    // ── state machine ──
    localparam S_IDLE       = 3'd0,
               S_TX_SS      = 3'd1,  // assert SS, load first byte
               S_TX_START   = 3'd2,  // pulse spi_start
               S_TX_WAIT    = 3'd3,  // wait for spi_done, advance or move on
               S_GAP        = 3'd4,  // inter-frame gap (SS high)
               S_RX_SS      = 3'd5,  // assert SS, load dummy byte
               S_RX_START   = 3'd6,  // pulse spi_start
               S_RX_WAIT    = 3'd7;  // wait for spi_done, store rx, advance or finish

    reg [2:0] state;
    reg [3:0] byte_idx;
    reg [3:0] gap_cnt;

    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            spi_data_in <= 8'd0;
            spi_start   <= 1'b0;
            ss          <= 1'b1;
            done        <= 1'b0;
            busy        <= 1'b0;
            byte_idx    <= 4'd0;
            gap_cnt     <= 4'd0;
            for (i = 0; i < 16; i = i + 1)
                rx_buf[i] <= 8'd0;
        end else begin
            spi_start <= 1'b0;
            done      <= 1'b0;

            case (state)
                // ────────────────────────────────────────────
                S_IDLE: begin
                    if (go) begin
                        busy     <= 1'b1;
                        byte_idx <= 4'd0;
                        state    <= S_TX_SS;
                    end
                end

                // ── TX frame: 16 bytes under one SS assertion ──
                S_TX_SS: begin
                    ss          <= 1'b0;                  // assert SS
                    spi_data_in <= tx_buf[byte_idx];
                    state       <= S_TX_START;
                end

                S_TX_START: begin
                    spi_start <= 1'b1;
                    state     <= S_TX_WAIT;
                end

                S_TX_WAIT: begin
                    if (spi_done) begin
                        if (byte_idx == 4'd15) begin
                            // all 16 bytes sent
                            ss       <= 1'b1;            // deassert SS
                            gap_cnt  <= 4'd0;
                            byte_idx <= 4'd0;
                            state    <= S_GAP;
                        end else begin
                            // next byte (SS stays low)
                            byte_idx    <= byte_idx + 1;
                            spi_data_in <= tx_buf[byte_idx + 1];
                            state       <= S_TX_START;
                        end
                    end
                end

                // ── inter-frame gap ──
                S_GAP: begin
                    gap_cnt <= gap_cnt + 1;
                    if (gap_cnt == 4'd9) begin
                        state <= S_RX_SS;
                    end
                end

                // ── RX frame: 16 bytes under one SS assertion ──
                S_RX_SS: begin
                    ss          <= 1'b0;                  // assert SS
                    spi_data_in <= 8'h00;                 // dummy TX
                    state       <= S_RX_START;
                end

                S_RX_START: begin
                    spi_start <= 1'b1;
                    state     <= S_RX_WAIT;
                end

                S_RX_WAIT: begin
                    if (spi_done) begin
                        rx_buf[byte_idx] <= spi_data_out;
                        if (byte_idx == 4'd15) begin
                            // all 16 bytes received
                            ss    <= 1'b1;                // deassert SS
                            done  <= 1'b1;
                            busy  <= 1'b0;
                            state <= S_IDLE;
                        end else begin
                            byte_idx    <= byte_idx + 1;
                            spi_data_in <= 8'h00;         // dummy TX
                            state       <= S_RX_START;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
