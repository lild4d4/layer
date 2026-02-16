module auth_challenge(
    input logic clk,
    input logic rst,
    input logic ready,
    input logic result_valid,
    input logic aes_core_ready,
    input logic [127:0] input_cipher,
    input logic [127:0] aes_core_result,
    input reg [127:0] input_key,

    output logic [127:0] key,
    output logic [127:0] block,
    output logic encdec,
    output logic aes_core_init,
    output logic aes_core_next,
    output logic valid
);

wire random_valid;
wire random_ready;
wire aes_handler_valid;
wire [63:0] random_value;

logic random_load;
logic aes_handler_ready;

reg decrypt_ready;
reg [63:0] rc;
reg [63:0] rt;
reg [127:0] challenge;
reg [127:0] session_key;

auth_aes_handler u_aes_handler(
    .clk(clk),
    .rst(rst),
    .ready(aes_handler_ready),
    .aes_core_ready(aes_core_ready),
    .result_valid(result_valid),

    .valid(aes_handler_valid),
    .aes_core_init(aes_core_init),
    .aes_core_next(aes_core_next)
);

auth_random u_random(
    .clk(clk),
    .rst(rst),
    .load(random_load),
    .seed(rc),

    .rnd(random_value),
    .valid(random_valid),
    .ready(random_ready)
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
        key <= 128'h0;
        block <= 128'h0;
        valid <= 1'b0;
        challenge <= 128'h0;
        session_key <= 128'h0;
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

always_comb begin
    next_state = state;
    encdec = 1'b0;
    valid = 1'b0;
    aes_handler_ready = 1'b0;
    random_load = 1'b0;

    case(state)
        IDLE: begin
            if (ready) next_state = DECRYPT;
        end

        DECRYPT: begin
            aes_handler_ready = 1'b1;
            encdec = 1'b0;
            key = input_key;
            block = input_cipher;

            if (aes_handler_valid) begin
                rc = aes_core_result[127:64];
                next_state = GET_RANDOM;
            end
        end

        GET_RANDOM: begin
            if (random_ready && !random_valid) begin
                random_load = 1'b1;
            end

            if (random_valid) begin
                rt = random_value;
                next_state = ENCRYPT_CHALLENGE;
            end
        end

        ENCRYPT_CHALLENGE: begin
            aes_handler_ready = 1'b1;
            encdec = 1'b0;
            key = input_key;
            block = {rt, rc};

            if (aes_handler_valid) begin
                challenge = aes_core_result;
                next_state = ENCRYPT_SESSION_KEY;
            end
        end

        ENCRYPT_SESSION_KEY: begin
            aes_handler_ready = 1'b1;
            encdec = 1'b0;
            key = input_key;
            block = {rc, rt};

            if (aes_handler_valid) begin
                valid = 1'b1;
                session_key = aes_core_result;
                next_state = IDLE;
            end
        end

        default: next_state = IDLE;

    endcase
end

endmodule
