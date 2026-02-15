module spi_top(
    input         clk,
    (* MARK_DEBUG = "TRUE" *) input         rst,

    (* MARK_DEBUG = "TRUE" *) output logic [3:0] led,

    // SPI bus
    (* MARK_DEBUG = "TRUE" *) output wire       sclk,
    (* MARK_DEBUG = "TRUE" *) output wire       mosi,
    input  wire       miso,
    output reg        ss
);

logic go, done, busy;
logic spi_clk;
logic spi_clk_d;  // delayed version for edge detection
logic spi_clk_en; // one-cycle pulse on rising edge of spi_clk
reg [23:0] ctr;

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

// SPI master now runs on clk with a clock enable
spi_master u_spi (
    .clk     (clk),
    .clk_en  (spi_clk_en),
    .reset   (rst),
    .data_in (8'b10101010),
    .start   (go),
    .miso    (miso),
    .mosi    (mosi),
    .sclk    (sclk),
    .data_out(),
    .done    (done),
    .busy    (busy)
);

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        ctr <= 99_999;
        go  <= 0;
        led <= 4'b0000;
        ss  <= 1;
    end else if (spi_clk_en) begin
        go <= 0;
        if (ctr == 0) begin
            if (~busy) begin
                ctr    <= 99_999;
                go     <= 1;
                ss     <= 0;
                led[0] <= ~led[0];
            end
        end else begin
            ctr <= ctr - 1;
        end
    end
end

endmodule
