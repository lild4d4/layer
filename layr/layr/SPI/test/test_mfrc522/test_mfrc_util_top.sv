module top_mfrc_version (
    input  wire clk,
    input  wire rst,

    input  wire start,
    output wire ready,
    output wire done,
    output wire ok,
    output wire [7:0] version,

    // Physical SPI pins
    output wire sclk,
    output wire mosi,
    input  wire miso,
    output wire cs0,   // MFRC522 chip select
    output wire cs1    // unused here (stays high), handy later for EEPROM
);

    // util <-> spi_ctrl wires
    wire        spi_go;
    wire        spi_done;
    wire        spi_busy;
    wire [5:0]  spi_w_len;
    wire [5:0]  spi_r_len;
    wire        spi_cs_sel;
    wire [255:0] spi_tx_data;
    wire [255:0] spi_rx_data;

    mfrc_util u_util (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .ready      (ready),
        .done       (done),
        .ok         (ok),
        .version    (version),

        .spi_go     (spi_go),
        .spi_done   (spi_done),
        .spi_busy   (spi_busy),
        .spi_w_len  (spi_w_len),
        .spi_r_len  (spi_r_len),
        .spi_cs_sel (spi_cs_sel),
        .spi_tx_data(spi_tx_data),
        .spi_rx_data(spi_rx_data)
    );

    spi_ctrl u_spi_ctrl (
        .clk     (clk),
        .rst     (rst),

        .go      (spi_go),
        .done    (spi_done),
        .busy    (spi_busy),

        .w_len   (spi_w_len),
        .r_len   (spi_r_len),

        .cs_sel  (spi_cs_sel),

        .tx_data (spi_tx_data),
        .rx_data (spi_rx_data),

        .sclk    (sclk),
        .mosi    (mosi),
        .miso    (miso),
        .cs0     (cs0),
        .cs1     (cs1)
    );

endmodule