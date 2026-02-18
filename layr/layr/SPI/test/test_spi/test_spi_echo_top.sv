// Thin top-level wrapper so cocotb can drive the control signals
// and attach a SPI slave model to the bus.

module test_spi_echo_top (
    input wire clk,
    input wire rst,

    // Control
    input  wire       go,
    input  wire [7:0] tx_byte,
    output wire [7:0] rx_byte,
    output wire       done,
    output wire       busy,

    // SPI bus – directly accessible by the cocotb slave
    output wire sclk,
    output wire mosi,
    input  wire miso,
    output wire ss
);

logic spi_clk;
logic spi_clk_d;  // delayed version for edge detection
logic spi_clk_en; // one-cycle pulse on rising edge of spi_clk

    clock_divider divider(
        .clk(clk),
        .rst(rst),
        .clk_out(spi_clk)
    );

    // Detect rising edge of spi_clk in the clk domain
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            spi_clk_d <= 0;
        else
            spi_clk_d <= spi_clk;
    end
    assign spi_clk_en = spi_clk & ~spi_clk_d;

  spi_echo u_echo (
      .clk    (clk),
      .rst    (rst),
      .spi_clk_en  (spi_clk_en),
      .go     (go),
      .tx_byte(tx_byte),
      .rx_byte(rx_byte),
      .done   (done),
      .busy   (busy),
      .sclk   (sclk),
      .mosi   (mosi),
      .miso   (miso),
      .ss     (ss)
  );

endmodule

