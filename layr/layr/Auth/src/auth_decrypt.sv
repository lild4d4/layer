module auth_decrypt(
    input logic clk,
    input logic rst,
    input logic start_i,
    input logic [31:0] aes_read_data_i,
    input logic [127:0] input_cipher_i,

    output logic        valid_o,
    output logic        aes_cs_o,
    output logic        aes_we_o,
    output logic [7:0]  aes_address_o,
    output logic [31:0] aes_write_data_o,
    output logic [63:0] rc
);

enum {
    IDLE,
    WRITE_MODE,
    WRITE_KEY,
    WRITE_INIT,
    READ_READY,
    WRITE_BLOCK,
    WRITE_NEXT,
    READ_VALID,
    READ_RESULT
} state, next_state;

localparam ADDR_CTRL    = 8'h08;
localparam ADDR_STATUS  = 8'h09;
localparam ADDR_CONFIG  = 8'h0a;
localparam ADDR_KEY0    = 8'h10;
localparam ADDR_BLOCK0  = 8'h20;
localparam ADDR_RESULT0 = 8'h30;

logic [1:0] key_count;
logic [1:0] block_count;
logic [1:0] result_count;

reg           ready_buffer_reg;
reg   [127:0] plain_reg;

always_ff @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        key_count <= 2'd0;
        block_count <= 2'd0;
        result_count <= 2'd0;
        ready_buffer_reg <= 1'b0;
        plain_reg <= 128'd0;
        rc <= 64'd0;

    end else begin
        state <= next_state;

        if (state == WRITE_BLOCK) begin
            block_count <= block_count + 2'd1;

        end else if (state == WRITE_KEY) begin
            key_count <= key_count + 2'd1;

        end else if (state == READ_RESULT) begin
            plain_reg[127 - (result_count*32) -: 32] <= aes_read_data_i;
            result_count <= result_count + 2'd1;

        end

    end
end

always_comb begin
    aes_cs_o = 1'b0;
    aes_we_o = 1'b0;
    aes_address_o = 8'd0;
    aes_write_data_o = 32'd0;
    next_state = state;

    case(state)
        IDLE: begin
            if (start_i) begin
                next_state = WRITE_KEY;
            end
        end

        WRITE_KEY: begin
            aes_cs_o = 1'b1;
            aes_we_o = 1'b1;
            aes_address_o = ADDR_KEY0 + key_count;
            // TODO: placeholder key
            case (key_count)
                2'b00: aes_write_data_o = 32'h2b7e1516;
                2'b01: aes_write_data_o = 32'h28aed2a6;
                2'b10: aes_write_data_o = 32'habf71588;
                2'b11: aes_write_data_o = 32'h09cf4f3c;
            endcase

            if (key_count == 2'd3) begin
                next_state = WRITE_MODE;
            end
        end

        WRITE_MODE: begin
            aes_cs_o = 1'b1;
            aes_we_o = 1'b1;
            aes_address_o = ADDR_CONFIG;
            aes_write_data_o = 8'h00;

            next_state = WRITE_INIT;
        end

        WRITE_INIT: begin
            aes_cs_o = 1'b1;
            aes_we_o = 1'b1;
            aes_address_o = ADDR_CTRL;
            aes_write_data_o = 8'h01;

            next_state = READ_READY;
        end

        READ_READY: begin
            aes_cs_o = 1'b1;
            aes_we_o = 1'b0;
            aes_address_o = ADDR_STATUS;

            if (aes_read_data_i[0]) begin
                next_state = WRITE_BLOCK;
            end
        end

        WRITE_BLOCK: begin
            aes_cs_o = 1'b1;
            aes_we_o = 1'b1;
            aes_address_o = ADDR_BLOCK0 + block_count;
            aes_write_data_o = input_cipher_i[127 - (block_count*32) -: 32];

            if (block_count == 2'd3) begin
                next_state = WRITE_NEXT;
            end
        end

        WRITE_NEXT: begin
            aes_cs_o = 1'b1;
            aes_we_o = 1'b1;
            aes_address_o = ADDR_CTRL;
            aes_write_data_o = 32'b10;

            next_state = READ_VALID;
        end

        READ_VALID: begin
            aes_cs_o = 1'b1;
            aes_we_o = 1'b0;
            aes_address_o = ADDR_STATUS;

            if (aes_read_data_i[1]) begin
                next_state = READ_RESULT;
            end
        end

        READ_RESULT: begin
            aes_cs_o = 1'b1;
            aes_we_o = 1'b0;
            aes_address_o = ADDR_RESULT0 + result_count;

            if (result_count == 2'd3) begin
                rc = plain_reg[127:64];
                valid_o = 1'b1;
                next_state = IDLE;
            end
        end

        default: next_state = IDLE;
    endcase
end

endmodule
