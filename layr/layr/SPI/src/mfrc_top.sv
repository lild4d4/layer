
module mfrc_top (
    input  wire clk,
    input  wire rst,

    // mfrc_core transceive API
    input  wire         trx_valid,
    output wire         trx_ready,
    input  wire [4:0]   trx_tx_len,
    input  wire [255:0] trx_tx_data,
    input  wire [2:0]   trx_tx_last_bits,
    input  wire [31:0]  trx_timeout_cycles,

    output wire         trx_done,
    output wire         trx_ok,
    output wire [4:0]   trx_rx_len,
    output wire [255:0] trx_rx_data,
    output wire [2:0]   trx_rx_last_bits,
    output wire [7:0]   trx_error,

    // util API (VersionReg read)
    input  wire       ver_valid,
    output wire       ver_ready,
    output wire       ver_done,
    output wire       ver_ok,
    output wire [7:0] ver_value,

    // connection to spi_ctrl (from shared mfrc_reg_if)
    output wire         spi_go,
    input  wire         spi_done,
    input  wire         spi_busy,
    output wire [5:0]   spi_w_len,
    output wire [5:0]   spi_r_len,
    output wire         spi_cs_sel,
    output wire [255:0] spi_tx_data,
    input  wire [255:0] spi_rx_data
);

    // -------- Client A: mfrc_core <-> arbiter wires --------
    wire         core_req_valid, core_req_ready, core_req_write;
    wire [5:0]   core_req_addr;
    wire [4:0]   core_req_len;
    wire [255:0] core_req_wdata;

    wire         core_resp_valid, core_resp_ok;
    wire [255:0] core_resp_rdata;

    // -------- Client B: mfrc_util <-> arbiter wires --------
    wire         util_req_valid, util_req_ready, util_req_write;
    wire [5:0]   util_req_addr;
    wire [4:0]   util_req_len;
    wire [255:0] util_req_wdata;

    wire         util_resp_valid, util_resp_ok;
    wire [255:0] util_resp_rdata;

    // -------- Shared: arbiter <-> mfrc_reg_if wires --------
    wire         s_req_valid, s_req_ready, s_req_write;
    wire [5:0]   s_req_addr;
    wire [4:0]   s_req_len;
    wire [255:0] s_req_wdata;

    wire         s_resp_valid, s_resp_ok;
    wire [255:0] s_resp_rdata;

    mfrc_core u_core (
        .clk(clk), .rst(rst),

        .trx_valid(trx_valid),
        .trx_ready(trx_ready),
        .trx_tx_len(trx_tx_len),
        .trx_tx_data(trx_tx_data),
        .trx_tx_last_bits(trx_tx_last_bits),
        .trx_timeout_cycles(trx_timeout_cycles),

        .trx_done(trx_done),
        .trx_ok(trx_ok),
        .trx_rx_len(trx_rx_len),
        .trx_rx_data(trx_rx_data),
        .trx_rx_last_bits(trx_rx_last_bits),
        .trx_error(trx_error),

        .reg_req_valid(core_req_valid),
        .reg_req_ready(core_req_ready),
        .reg_req_write(core_req_write),
        .reg_req_addr (core_req_addr),
        .reg_req_len  (core_req_len),
        .reg_req_wdata(core_req_wdata),

        .reg_resp_valid(core_resp_valid),
        .reg_resp_rdata(core_resp_rdata),
        .reg_resp_ok   (core_resp_ok)
    );

    mfrc_util u_util (
        .clk(clk), .rst(rst),

        .ver_valid(ver_valid),
        .ver_ready(ver_ready),
        .ver_done(ver_done),
        .ver_ok(ver_ok),
        .ver_value(ver_value),

        .reg_req_valid(util_req_valid),
        .reg_req_ready(util_req_ready),
        .reg_req_write(util_req_write),
        .reg_req_addr (util_req_addr),
        .reg_req_len  (util_req_len),
        .reg_req_wdata(util_req_wdata),

        .reg_resp_valid(util_resp_valid),
        .reg_resp_rdata(util_resp_rdata),
        .reg_resp_ok   (util_resp_ok)
    );

    mfrc_reg_arb u_arb (
        .clk(clk), .rst(rst),

        .a_req_valid(core_req_valid),
        .a_req_ready(core_req_ready),
        .a_req_write(core_req_write),
        .a_req_addr (core_req_addr),
        .a_req_len  (core_req_len),
        .a_req_wdata(core_req_wdata),
        .a_resp_valid(core_resp_valid),
        .a_resp_rdata(core_resp_rdata),
        .a_resp_ok   (core_resp_ok),

        .b_req_valid(util_req_valid),
        .b_req_ready(util_req_ready),
        .b_req_write(util_req_write),
        .b_req_addr (util_req_addr),
        .b_req_len  (util_req_len),
        .b_req_wdata(util_req_wdata),
        .b_resp_valid(util_resp_valid),
        .b_resp_rdata(util_resp_rdata),
        .b_resp_ok   (util_resp_ok),

        .s_req_valid(s_req_valid),
        .s_req_ready(s_req_ready),
        .s_req_write(s_req_write),
        .s_req_addr (s_req_addr),
        .s_req_len  (s_req_len),
        .s_req_wdata(s_req_wdata),

        .s_resp_valid(s_resp_valid),
        .s_resp_rdata(s_resp_rdata),
        .s_resp_ok   (s_resp_ok)
    );

    mfrc_reg_if u_reg_if (
        .clk(clk), .rst(rst),

        .req_valid(s_req_valid),
        .req_ready(s_req_ready),
        .req_write(s_req_write),
        .req_addr (s_req_addr),
        .req_len  (s_req_len),
        .req_wdata(s_req_wdata),

        .resp_valid(s_resp_valid),
        .resp_rdata(s_resp_rdata),
        .resp_ok   (s_resp_ok),

        .spi_go(spi_go),
        .spi_done(spi_done),
        .spi_busy(spi_busy),
        .spi_w_len(spi_w_len),
        .spi_r_len(spi_r_len),
        .spi_cs_sel(spi_cs_sel),
        .spi_tx_data(spi_tx_data),
        .spi_rx_data(spi_rx_data)
    );

endmodule
