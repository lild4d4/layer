module test_spi_ctrl_top(
    input         clk,
    (* MARK_DEBUG = "TRUE" *) input         rst,

    (* MARK_DEBUG = "TRUE" *) output logic [3:0] led,

    // SPI bus
    (* MARK_DEBUG = "TRUE" *) output wire       sclk,
    (* MARK_DEBUG = "TRUE" *) output wire       mosi,
    input  wire       miso,
    (* MARK_DEBUG = "TRUE" *) output wire       cs0,
    (* MARK_DEBUG = "TRUE" *) output wire       cs1,
    (* MARK_DEBUG = "TRUE" *) output logic [7:0] last_read
);

logic go, done, busy;
reg [23:0] ctr;

wire [255:0] rx_data;

spi_ctrl u_dut (
    .clk    (clk),
    .rst    (rst),
    .go     (go),
    .done   (done),
    .busy   (busy),
    .w_len  (6'd4),
    .r_len  (6'd4),
    .cs_sel (1'b0),
    .tx_data({8'hDE, 8'hAD, 8'hBE, 8'hEF, 224'd0}),
    .rx_data(rx_data),
    .sclk   (sclk),
    .mosi   (mosi),
    .miso   (miso),
    .cs0    (cs0),
    .cs1    (cs1)
);

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        last_read <= 0;
    end else begin
        if (done)
            last_read <= rx_data[255:248];
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        ctr <= 500;
        go  <= 0;
        led <= 4'b0001;
    end else begin
        go <= 0;
        if (ctr == 0) begin
            if (~busy) begin
                ctr    <= 20_000;
                go     <= 1;
                led[0] <= ~led[0];
            end
        end else begin
            ctr <= ctr - 1;
        end
    end
end

endmodule
