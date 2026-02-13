// test_mfrc_reg_if_top – testbench wrapper
//
// Instantiates mfrc_reg_if → spi_ctrl → spi_master, exposing the
// request interface and SPI bus signals to cocotb.

module test_mfrc_reg_if_top (
    input  wire          clk,
    input  wire          rst_n,

    // ── request side ──
    input  wire          req_valid,
    output wire          req_ready,
    input  wire          req_write,
    input  wire [5:0]    req_addr,
    input  wire [5:0]    req_len,
    input  wire [255:0]  req_wdata,

    // ── response side ──
    output wire          resp_valid,
    output wire [255:0]  resp_rdata,
    output wire          resp_ok,

    // ── SPI bus (directly accessible by cocotb slave) ──
    output wire          sclk,
    output wire          mosi,
    input  wire          miso,
    output wire          cs0,
    output wire          cs1
);

    // Wires between mfrc_reg_if and spi_ctrl
    wire          spi_go;
    wire          spi_done;
    wire          spi_busy;
    wire [5:0]    spi_w_len;
    wire [5:0]    spi_r_len;
    wire          spi_cs_sel;
    wire [255:0]  spi_tx_data;
    wire [255:0]  spi_rx_data;

    mfrc_reg_if u_reg_if (
        .clk         (clk),
        .rst_n       (rst_n),

        .req_valid   (req_valid),
        .req_ready   (req_ready),
        .req_write   (req_write),
        .req_addr    (req_addr),
        .req_len     (req_len),
        .req_wdata   (req_wdata),

        .resp_valid  (resp_valid),
        .resp_rdata  (resp_rdata),
        .resp_ok     (resp_ok),

        .spi_go      (spi_go),
        .spi_done    (spi_done),
        .spi_busy    (spi_busy),
        .spi_w_len   (spi_w_len),
        .spi_r_len   (spi_r_len),
        .spi_cs_sel  (spi_cs_sel),
        .spi_tx_data (spi_tx_data),
        .spi_rx_data (spi_rx_data)
    );

    spi_ctrl u_spi_ctrl (
        .clk     (clk),
        .rst_n   (rst_n),

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
