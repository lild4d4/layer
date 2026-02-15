module auth_decrypt(
    input logic clk,
    input logic rst,
    input logic ready,
    input logic aes_core_ready,
    input logic result_valid,
    input logic [127:0] result,

    output logic [127:0] key,
    output logic [127:0] block,
    output logic encdec,
    output logic valid,
    output logic aes_core_init,
    output logic aes_core_next
);

enum {
    IDLE,
    WRITE_KEY,
    READ_READY,
    WRITE_BLOCK,
    WRITE_MODE_AGAIN,
    WRITE_NEXT,
    READ_VALID,
    READ_RESULT
} state, next_state;

assign valid = result_valid;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        aes_core_init <= 1'b0;
        aes_core_next <= 1'b0;
        block <= 128'b0;
        key <= 128'b0;
        state <= IDLE;

    end else begin
        state <= next_state;

    end
end

always_comb begin
    next_state = state;
    aes_core_init = 1'b0;
    aes_core_next = 1'b0;

    case(state)
        IDLE: begin
            if (ready) begin
                next_state = WRITE_KEY;
            end
        end

        WRITE_KEY: begin
            key = 128'h2b7e151628aed2a6abf7158809cf4f3c;
            aes_core_init = 1'b1;
            next_state = READ_READY;
        end

        READ_READY: begin
            if (aes_core_ready) begin
                next_state = WRITE_BLOCK;
            end
        end

        WRITE_BLOCK: begin
            block = 128'h3ad77bb40d7a3660a89ecaf32466ef97;
            aes_core_next = 1'b1;
            next_state = READ_VALID;
        end

        READ_VALID: begin
            if (result_valid) begin
                next_state = IDLE;
            end
        end

        default: next_state = IDLE;
    endcase
end

endmodule
