// spi_echo – sends one byte through spi_master, then performs a
// second transaction to read the slave's echo reply.
//
// The external test-bench slave is responsible for capturing the
// first byte and replying with it during the second transaction.
//
// SS is managed here (the parent of spi_master), keeping it low
// for each byte transfer and raising it between transactions.

module spi_echo (
    input  wire       clk,
    input  wire       rst_n,      // active-low reset

    // Control interface
    input  wire       go,         // pulse high for 1 clk to start
    input  wire [7:0] tx_byte,    // byte to send in the first transaction
    output reg  [7:0] rx_byte,    // echoed byte received in the second transaction
    output reg        done,       // pulses high for 1 clk when rx_byte is valid
    output reg        busy,       // high while a sequence is in progress

    // SPI bus (directly exposed to pads / testbench)
    output wire       sclk,
    output wire       mosi,
    input  wire       miso,
    output reg        ss
);

    // ── internal wires to spi_master ──
    reg  [7:0] spi_data_in;
    reg        spi_start;
    wire [7:0] spi_data_out;
    wire       spi_done;
    wire       spi_busy;

    spi_master u_spi (
        .clk      (clk),
        .reset    (~rst_n),       // spi_master uses active-high reset
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
               S_TX_START   = 3'd1,
               S_TX_WAIT    = 3'd2,
               S_GAP        = 3'd3,
               S_RX_START   = 3'd4,
               S_RX_WAIT    = 3'd5,
               S_DONE       = 3'd6;

    reg [2:0] state;
    reg [3:0] gap_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            spi_data_in <= 8'd0;
            spi_start   <= 1'b0;
            ss          <= 1'b1;     // SS idle high
            rx_byte     <= 8'd0;
            done        <= 1'b0;
            busy        <= 1'b0;
            gap_cnt     <= 4'd0;
        end else begin
            // defaults
            spi_start <= 1'b0;
            done      <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (go) begin
                        busy        <= 1'b1;
                        spi_data_in <= tx_byte;
                        ss          <= 1'b0;     // assert SS
                        state       <= S_TX_START;
                    end
                end

                // ── first transaction: send tx_byte ──
                S_TX_START: begin
                    spi_start <= 1'b1;
                    state     <= S_TX_WAIT;
                end

                S_TX_WAIT: begin
                    if (spi_done) begin
                        ss      <= 1'b1;         // deassert SS
                        gap_cnt <= 4'd0;
                        state   <= S_GAP;
                    end
                end

                // ── gap between transactions ──
                S_GAP: begin
                    gap_cnt <= gap_cnt + 1;
                    if (gap_cnt == 4'd9) begin
                        spi_data_in <= 8'h00;    // dummy TX for read
                        ss          <= 1'b0;     // assert SS
                        state       <= S_RX_START;
                    end
                end

                // ── second transaction: read echo ──
                S_RX_START: begin
                    spi_start <= 1'b1;
                    state     <= S_RX_WAIT;
                end

                S_RX_WAIT: begin
                    if (spi_done) begin
                        ss      <= 1'b1;         // deassert SS
                        rx_byte <= spi_data_out;
                        state   <= S_DONE;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
