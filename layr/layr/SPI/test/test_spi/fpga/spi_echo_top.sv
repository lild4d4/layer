module spi_echo_top(
    input         clk,
    (* MARK_DEBUG = "TRUE" *) input         rst,

    (* MARK_DEBUG = "TRUE" *) output logic [3:0] led,

    // SPI bus
    (* MARK_DEBUG = "TRUE" *) output wire       sclk,
    (* MARK_DEBUG = "TRUE" *) output wire       mosi,
    input  wire       miso,
    (* MARK_DEBUG = "TRUE" *) output reg        ss,
    (* MARK_DEBUG = "TRUE" *) output logic [7:0] last_read
);

logic go, done, busy;
logic spi_clk;
logic spi_clk_d;  // delayed version for edge detection
logic spi_clk_en; // one-cycle pulse on rising edge of spi_clk
logic [7:0] rx;
reg [23:0] ctr;
reg [7:0] send_num;

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
spi_echo u_spi (
    .clk     (clk),
    .spi_clk_en  (spi_clk_en),
    .rst   (rst),
    .tx_byte (send_num),
    .rx_byte (rx),
    .go   (go),
    .miso    (miso),
    .mosi    (mosi),
    .sclk    (sclk),
    .done    (done),
    .busy    (busy),
    .ss      (ss)
);

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        last_read <= 0;
    end else begin
        if (done)
            last_read <= rx;
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        ctr <= 10_000;
        go  <= 1;
        led <= 4'b0000;
        send_num <= 1;
    end else if (spi_clk_en) begin
        go <= 0;
        if (ctr == 0) begin
            if (~busy) begin
                ctr    <= 10_000;
                go     <= 1;
                led[0] <= ~led[0];
                send_num <= send_num + 1;
            end
        end else begin
            ctr <= ctr - 1;
        end
    end
end

endmodule
