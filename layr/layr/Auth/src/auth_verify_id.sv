module auth_verify_id(
    input logic clk,
    input logic rst,
    input logic ready,
    input logic result_valid,
    input logic aes_core_ready,
    input logic [127:0] input_cipher,
    input logic [127:0] aes_core_result,
    input reg [127:0] input_key,

    output logic valid,
    output logic encdec,
    output logic aes_core_init,
    output logic aes_core_next,
    output logic [127:0] key,
    output logic [127:0] block,
    output reg id_valid
);

enum {
    IDLE,
    DECRYPT,
    CHECK_ID
} state, next_state;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= IDLE;
    end
end

endmodule
