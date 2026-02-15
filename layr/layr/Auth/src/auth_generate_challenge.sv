module auth_generate_challenge(
    input  logic         clk,
    input  logic         rst,
    input  logic         ready_i,
    input  logic [127:0] input_cipher_i,
    input  logic [31:0]  aes_read_data_i,

    output logic         error_o,
    output logic         challenge_valid_o,
    output logic [127:0] challenge_response_o,

    // AES‑core interface
    output logic         aes_cs_o,
    output logic         aes_we_o,
    output logic [7:0]   aes_address_o,
    output logic [31:0]  aes_write_data_o
);

enum {
    DECRYPT,
    GET_RANDOM,
    ENCRYPT,
    SEND
} state, next_state;

reg [63:0] rc_reg;

auth_decrypt decrypt(
    .clk(clk),
    .rst(rst),
    .start_i(ready_i),
    .aes_read_data_i(aes_read_data_i),
    .input_cipher_i(input_cipher_i),

    .aes_cs_o(aes_cs_o),
    .aes_we_o(aes_we_o),
    .aes_address_o(aes_address_o),
    .aes_write_data_o(aes_write_data_o),
    .rc(rc_reg)
);

endmodule
