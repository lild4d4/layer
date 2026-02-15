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
    //       data_i as input.
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
    input reg [127:0] data_i,
    output reg [127:0] data_o,
    output wire valid_o
);

wire encdec;
wire aes_core_init;
wire aes_core_next;
wire aes_core_ready;
wire [127:0] key;
wire [127:0] block;
wire [127:0] result;
wire result_valid;

assign ready = start_i;

assign valid_o = result_valid;

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
    .ready(ready),
    .result_valid(result_valid),
    .result(result),

    .key(key),
    .block(block),
    .encdec(encdec),
    .aes_core_init(aes_core_init),
    .aes_core_next(aes_core_next),
    .aes_core_ready(aes_core_ready)
);

endmodule
