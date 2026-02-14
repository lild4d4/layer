module spi_top(
    input         clk,
    input         rst,

    
    output wire [3:0] led,

    // SPI bus
    output wire       sclk,
    output wire       mosi,
    input  wire       miso,
    output reg        ss
);

spi_echo echo (
    .clk(clk),
    .rst(rst),

    // Control interface
    .go(~rst),
    .tx_byte(8'h2),

    .sclk(sclk),
    .mosi(mosi),
    .miso(miso),
    .ss(ss)
);

assign led[0] = rst;


endmodule