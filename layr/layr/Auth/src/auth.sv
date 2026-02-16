module auth(
    //--------------------------------------
    // = Required =
    //--------------------------------------
    input wire clk,
    input wire rst,

    //--------------------------------------
    // = Control =
    //
    // operation_i:
    //   0 = Generate challenge response
    //   1 = Verify ID
    //
    // start_i:
    //   0 = Do nothing
    //   1 = Run selected operation with
    //       data_i as input. Has to stay set
    //       until valid_o becomes true.
    //--------------------------------------
    input tri0 operation_i,
    input tri0 start_i,

    //--------------------------------------
    // = Data bus =
    //
    // data_i:
    //   Input data for any selected operation.
    //
    // data_o:
    //   Output data for any selected operation.
    //
    // valid_o:
    //   0 = the operation is still running
    //   1 = the operation is done, data
    //       can be read from data_o
    //--------------------------------------
    input  tri0 [127:0] data_i,
    output reg [127:0] data_o,
    output reg valid_o
);

enum {
    IDLE,
    GENERATE_CHALLENGE,
    VERIFY_ID
} state, next_state;

wire aes_core_init;
wire aes_core_next;
wire aes_core_ready;
wire result_valid;
wire auth_challenge_valid;
wire auth_challenge_encdec;
wire auth_verify_id_valid;
wire auth_verify_id_encdec;
wire [127:0] key;
wire [127:0] block;
wire [127:0] result;
wire [127:0] challenge_o;
wire [127:0] session_key_o;

logic generate_challenge_ready;
logic verify_id_ready;

reg id_valid;
reg [127:0] input_key;
reg [127:0] session_key;

aes_core u_aes_core(
    .clk(clk),
    .reset_n(!rst),
    .encdec(encdec),
    .init(aes_core_init),
    .next(aes_core_next),
    .key({key, 128'h0}),
    .keylen(1'b0),
    .block(block),

    .result(result),
    .ready(aes_core_ready),
    .result_valid(result_valid)
);

auth_challenge u_auth_challenge(
    .clk(clk),
    .rst(rst),
    .ready(generate_challenge_ready),
    .result_valid(result_valid),
    .input_cipher(data_i),
    .input_key(input_key),
    .aes_core_result(result),

    .key(key),
    .block(block),
    .encdec(encdec),
    .aes_core_init(aes_core_init),
    .aes_core_next(aes_core_next),
    .aes_core_ready(aes_core_ready),
    .valid(auth_challenge_valid),
    .challenge_o(challenge_o),
    .session_key_o(session_key_o)
);

auth_verify_id u_auth_verify_id(
    .clk(clk),
    .rst(rst),
    .ready(verify_id_ready),
    .result_valid(result_valid),
    .input_cipher(data_i),
    .input_key(session_key)
);

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        input_key <= 128'h0;
        session_key <= 128'h0;
        data_o <= 128'h0;
        generate_challenge_ready <= 1'b0;
        verify_id_ready <= 1'b0;
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

always_comb begin
    valid_o = 1'b0;

    case(state)
        IDLE: begin
            if (start_i) begin
                case(operation_i)
                    1'b0: next_state = GENERATE_CHALLENGE;
                    1'b1: next_state = VERIFY_ID;
                endcase
            end
        end

        GENERATE_CHALLENGE: begin
            generate_challenge_ready = 1'b1;

            if (auth_challenge_valid) begin
                session_key = session_key_o;
                data_o = challenge_o;
                valid_o = 1'b1;
                next_state = IDLE;
            end
        end

        VERIFY_ID: begin
            verify_id_ready = 1'b1;

            if (auth_verify_id_valid) begin
                data_o = {127'h0, id_valid};
                valid_o = 1'b1;
                next_state = IDLE;
            end
        end

        default: next_state = IDLE;
    endcase
end

endmodule
