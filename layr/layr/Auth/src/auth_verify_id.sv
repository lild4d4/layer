module auth_verify_id(
    input logic clk,
    input logic rst,
    input logic ready,
    input logic result_valid,
    input logic aes_core_ready,
    input logic [127:0] input_cipher,
    input logic [127:0] aes_core_result,

    output logic valid,
    output logic encdec,
    output logic aes_core_init,
    output logic aes_core_next,
    output logic [127:0] block_o,
    output reg id_valid,

    // EEPROM interface
    input logic eeprom_busy,
    input logic eeprom_done,
    input logic [127:0] eeprom_buffer,
    output logic eeprom_start,
    output logic eeprom_get_key
);


enum {
    IDLE,
    DECRYPT,
    GET_ID,
    WAIT_FOR_ID,
    CHECK_ID
} state, next_state;

logic aes_handler_ready;

reg [127:0] block, next_block;
reg [127:0] id, next_id;
reg [127:0] expected_id, next_expected_id;

assign block_o = block;

auth_aes_handler u_aes_handler(
    .clk(clk),
    .rst(rst),
    .ready(aes_handler_ready),
    .aes_core_ready(aes_core_ready),
    .result_valid(result_valid),

    .valid_o(aes_handler_valid),
    .aes_core_init(aes_core_init),
    .aes_core_next(aes_core_next)
);

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        id <= 128'h0;
        expected_id <= 128'h0;
        id_valid <= 1'b0;
        aes_handler_ready <= 1'b0;
        block <= 128'h0;
        expected_id <= 128'h0;
        state <= IDLE;
    end else begin
        state <= next_state;
        block <= next_block;
        id <= next_id;
        expected_id <= next_expected_id;
    end
end

always_comb begin
    valid = 1'b0;
    encdec = 1'b0;
    id_valid = 1'b0;
    eeprom_start = 1'b0;
    eeprom_get_key = 1'b0;
    aes_handler_ready = 1'b0;
    next_state = state;
    next_block = block;
    next_id = id;
    next_expected_id = expected_id;

    case(state)
        IDLE: begin
            if (ready) next_state = DECRYPT;
        end

        DECRYPT: begin
            next_block = input_cipher;

            if (!aes_handler_valid) begin
                aes_handler_ready = 1'b1;
            end else if (aes_handler_valid) begin
                next_id = aes_core_result;
                next_state = GET_ID;
            end
        end

        GET_ID: begin
            if (!eeprom_busy) begin
                eeprom_get_key = 1'b0;
                eeprom_start = 1'b1;
                next_state = WAIT_FOR_ID;
            end
        end

        WAIT_FOR_ID: begin
            if (eeprom_done) begin
                next_expected_id = eeprom_buffer;
                next_state = CHECK_ID;
            end
        end

        CHECK_ID: begin
            valid = 1'b1;
            if (id == expected_id) begin
                id_valid = 1'b1;
                next_state = IDLE;
            end else begin
                id_valid = 1'b0;
                next_state = IDLE;
            end
        end

        default: begin
            id_valid = 1'b0;
            next_state = IDLE;
        end
    endcase
end

endmodule
