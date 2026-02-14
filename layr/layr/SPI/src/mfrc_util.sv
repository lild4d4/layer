module mfrc_util (
    input  wire         clk,
    input  wire         rst,

    input  wire         start,
    output wire         ready,

    output reg          done,
    output reg          ok,
    output reg  [7:0]   version,

    // ---- spi_ctrl 
    output wire         spi_go,
    input  wire         spi_done,
    input  wire         spi_busy,
    output wire [5:0]   spi_w_len,
    output wire [5:0]   spi_r_len,
    output wire         spi_cs_sel,
    output wire [255:0] spi_tx_data,
    input  wire [255:0] spi_rx_data
);

    // VersionReg address
    localparam [5:0] REG_VERSION = 6'h37;

    // reg_if request/response
    reg          req_valid;
    wire         req_ready;
    reg          req_write;
    reg  [5:0]   req_addr;
    reg  [4:0]   req_len;
    reg  [255:0] req_wdata;

    wire         resp_valid;
    wire [255:0] resp_rdata;
    wire         resp_ok;

    // Shared register interface instance
    mfrc_reg_if u_reg_if (
        .clk        (clk),
        .rst        (rst),

        .req_valid  (req_valid),
        .req_ready  (req_ready),
        .req_write  (req_write),
        .req_addr   (req_addr),
        .req_len    (req_len),
        .req_wdata  (req_wdata),

        .resp_valid (resp_valid),
        .resp_rdata (resp_rdata),
        .resp_ok    (resp_ok),

        .spi_go     (spi_go),
        .spi_done   (spi_done),
        .spi_busy   (spi_busy),
        .spi_w_len  (spi_w_len),
        .spi_r_len  (spi_r_len),
        .spi_cs_sel (spi_cs_sel),
        .spi_tx_data(spi_tx_data),
        .spi_rx_data(spi_rx_data)
    );

    localparam [1:0]
        S_IDLE = 2'd0,
        S_WAIT = 2'd1;

    reg [1:0] state;

    // Ready only when idle and reg_if can accept a request
    assign ready = (state == S_IDLE) && req_ready;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            req_valid <= 1'b0;
            req_write <= 1'b0;
            req_addr  <= 6'd0;
            req_len   <= 5'd0;
            req_wdata <= 256'd0;
            done      <= 1'b0;
            ok        <= 1'b0;
            version   <= 8'd0;
        end else begin
            req_valid <= 1'b0;
            done      <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start && req_ready) begin
                        // 1-byte read of VersionReg
                        req_write <= 1'b0;
                        req_addr  <= REG_VERSION;
                        req_len   <= 5'd0;     // 0 -> 1 byte
                        req_wdata <= 256'd0;

                        req_valid <= 1'b1;     // pulse
                        state     <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (resp_valid) begin
                        version <= resp_rdata[255:248];
                        ok      <= resp_ok;
                        done    <= 1'b1;
                        state   <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule