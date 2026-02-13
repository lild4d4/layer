module test_spi_ctrl_top (
    input  wire          clk,
    input  wire          rst_n,

    // Control
    input  wire          go,
    output wire          done,
    output wire          busy,

    // Transfer lengths
    input  wire [5:0]    w_len,
    input  wire [5:0]    r_len,

    // Chip select
    input  wire          cs_sel,

    // Data
    input  wire [255:0]  tx_data,
    output wire [255:0]  rx_data,

    // SPI bus
    output wire          sclk,
    output wire          mosi,
    input  wire          miso,
    output wire          cs0,
    output wire          cs1
);

    spi_ctrl u_dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .go      (go),
        .done    (done),
        .busy    (busy),
        .w_len   (w_len),
        .r_len   (r_len),
        .cs_sel  (cs_sel),
        .tx_data (tx_data),
        .rx_data (rx_data),
        .sclk    (sclk),
        .mosi    (mosi),
        .miso    (miso),
        .cs0     (cs0),
        .cs1     (cs1)
    );

endmodule
