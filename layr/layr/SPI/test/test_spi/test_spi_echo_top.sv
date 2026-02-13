// Thin top-level wrapper so cocotb can drive the control signals
// and attach a SPI slave model to the bus.

module test_spi_echo_top (
    input  wire       clk,
    input  wire       rst_n,

    // Control
    input  wire       go,
    input  wire [7:0] tx_byte,
    output wire [7:0] rx_byte,
    output wire       done,
    output wire       busy,

    // SPI bus – directly accessible by the cocotb slave
    output wire       sclk,
    output wire       mosi,
    input  wire       miso,
    output wire       ss
);

    spi_echo u_echo (
        .clk     (clk),
        .rst_n   (rst_n),
        .go      (go),
        .tx_byte (tx_byte),
        .rx_byte (rx_byte),
        .done    (done),
        .busy    (busy),
        .sclk    (sclk),
        .mosi    (mosi),
        .miso    (miso),
        .ss      (ss)
    );

endmodule