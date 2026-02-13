module auth_verify_id(
    input logic clk,
    input logic rst,

    input logic ready_i,
    input logic [127:0] id_cipher_i,

    output logic error_o,
    output logic success_o,
    output reg aes_cs_o,
    output reg aes_we_o,
    output reg [7:0] aes_address_o,
    output reg [31:0] aes_write_data_o
);

    reg [127:0] reg_id_cipher;
    wire reset_aes_key;

    assign error_o = 1'b0;
    assign success_o = 1'b0;

    auth_init auth_init(
        .start_i(reset_aes_key)
    );

    // TODO: calculate session_key = AES_psk(rc || rt)
    // TODO: decrypt reg_id_cipher with session_key
    // TODO: Verify that card ID is allowed
    // TODO: If the card ID is in the allowed list, set success to 1

endmodule
