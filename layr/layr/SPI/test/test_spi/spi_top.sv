module spi_top(
    input         clk,
    (* MARK_DEBUG = "TRUE" *) input         rst,

    output logic [3:0] led,

    // SPI bus
    (* MARK_DEBUG = "TRUE" *) output wire       sclk,
    (* MARK_DEBUG = "TRUE" *) output wire       mosi,
    input  wire       miso,
    output reg        ss
);

logic go, done, busy;
logic spi_clk;
reg [23:0] ctr; // 24 bits to count up to 10,000,000

clock_divider divider(
    .clk(clk),
    .rst(rst),
    .clk_out(spi_clk)
);

spi_master u_spi (
    .clk     (spi_clk),
    .reset   (rst),
    .data_in (8'hbe),
    .start   (go),
    .miso    (miso),
    .mosi    (mosi),
    .sclk    (sclk),

    .busy(busy)
);

always_ff @(posedge spi_clk or posedge rst) begin
    if (rst) begin
        ctr <= 1;
        go <= 0;
        led <= 4'b0000;
        ss <= 0;
    end else begin
        if (ctr == 0) begin
            if(~busy)begin
                ctr <= 9_999_999;       // reset counter every 1 second
                go <= 1;        // pulse `go` for 1 clock cycle
                led[0] <= ~led[0]; // toggle only led[0]
            end
        end else begin
            ctr <= ctr - 1;
            go <= 0;
        end
    end
end

endmodule




