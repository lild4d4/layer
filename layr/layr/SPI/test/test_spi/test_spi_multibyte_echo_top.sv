module test_spi_multibyte_echo_top (
    input  wire        clk,
    input  wire        rst,

    // Control
    input  wire        go,
    output wire        done,
    output wire        busy,

    // RX buffer read port
    input  wire [3:0]  rx_addr,
    output wire [7:0]  rx_data,

    // SPI bus
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,
    output wire        ss
);

    spi_multibyte_echo u_dut (
        .clk     (clk),
        .rst   (rst),
        .go      (go),
        .done    (done),
        .busy    (busy),
        .rx_addr (rx_addr),
        .rx_data (rx_data),
        .sclk    (sclk),
        .mosi    (mosi),
        .miso    (miso),
        .ss      (ss)
    );

endmodule
