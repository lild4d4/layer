module auth_challenge(
    input logic clk,
    input logic rst,
    input logic ready,
    input logic result_valid,
    input logic aes_core_ready,
    input logic [127:0] result,

    output logic [127:0] key,
    output logic [127:0] block,
    output logic encdec,
    output logic aes_core_init,
    output logic aes_core_next,
    output logic valid
);

wire decrypt_valid;

reg decrypt_ready;
reg [63:0] rc;
reg [63:0] rt;

// TODO: Temporary, needs to be only valid after chal and session key are
// calculated.
assign valid = result_valid;

auth_decrypt u_auth_decrypt(
    .clk(clk),
    .rst(rst),
    .ready(decrypt_ready),
    .result_valid(result_valid),
    .result(result),

    .key(key),
    .block(block),
    .valid(decrypt_valid),
    .aes_core_init(aes_core_init),
    .aes_core_next(aes_core_next),
    .aes_core_ready(aes_core_ready)
);

enum {
    IDLE,
    DECRYPT,
    GET_RANDOM,
    ENCRYPT_CHALLENGE,
    ENCRYPT_SESSION_KEY
} state, next_state;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        rc <= 64'd0;
        rt <= 64'd0;
    end else begin
        state <= next_state;
        if (result_valid) rc <= result[127:64];
    end
end

always_comb begin
    next_state = state;
    decrypt_ready = 1'b0;

    case(state)
        IDLE: begin
            if (ready) next_state = DECRYPT;
        end

        DECRYPT: begin
            decrypt_ready = 1'b1;

            if (decrypt_valid) begin
                next_state = GET_RANDOM;
            end
        end

        GET_RANDOM: begin
            next_state = IDLE;
        end

        ENCRYPT_CHALLENGE: begin
            next_state = IDLE;
        end

        ENCRYPT_SESSION_KEY: begin
            next_state = IDLE;
        end

        default: next_state = IDLE;

    endcase
end

endmodule
