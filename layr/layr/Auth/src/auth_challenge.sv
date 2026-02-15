module auth_challenge(
    input logic         clk,
    input logic         rst,
    input logic         ready_i,
    input logic [31:0]  aes_read_data_i,
    input logic [127:0] input_cipher_i,

    output logic        aes_cs_o,
    output logic        aes_we_o,
    output logic [7:0]  aes_address_o,
    output logic [31:0] aes_write_data_o
);

// TODO: decrypt input_cipher_i
// TODO: Get random value rt
// TODO: encrypt rt || rc
// TODO: encrypt rc || rt
// TODO: Send rt || rc to LAYR module
// TODO: Send rc || rt to auth_verif_id module

endmodule
