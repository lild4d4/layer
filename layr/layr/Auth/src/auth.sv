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
    input wire operation_i,
    input wire start_i,

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
    // AES core connections
    wire aes_cs;
    wire aes_we;
    wire [7:0] aes_address;
    wire [31:0] aes_write_data;
    wire [31:0] aes_read_data;

    // auth_init connections
    wire auth_init_start_i;

    reg reg_operation;
    reg error;
    reg generate_challenge_valid;
    reg id_valid;

    aes aes(
        .clk(clk),
        .reset_n(!rst),

        //Inputs
        .cs(aes_cs),
        .we(aes_we),
        .address(aes_address),
        .write_data(aes_write_data),

        // Outputs
        .read_data(aes_read_data)
    );

    auth_init init(
        .clk(clk),
        .rst(rst),

        // Inputs
        .start_i(auth_init_start_i),

        // Outputs
        .aes_cs_o(aes_cs),
        .aes_we_o(aes_we),
        .aes_address_o(aes_address),
        .aes_write_data_o(aes_write_data)
    );

    auth_generate_challenge generate_challenge(
        .clk(clk),
        .rst(rst),

        // Inputs
        .ready_i(!reg_operation),
        .input_cipher_i(reg_data_i),
        .aes_read_data_i(aes_read_data),

        // Outputs
        .error_o(error),
        .challenge_valid_o(generate_challenge_valid),
        .data_o(reg_data_o),
        .aes_cs_o(aes_cs),
        .aes_we_o(aes_we),
        .aes_address_o(aes_address),
        .aes_write_data_o(aes_write_data)
    );

    auth_verify_id verify_id(
        .clk(clk),
        .rst(rst),

        // Inputs
        .ready_i(reg_operation),
        .id_cipher_i(reg_data_i),

        // Outputs
        .error_o(error),
        .success_o(id_valid)
        .aes_cs_o(aes_cs),
        .aes_we_o(aes_we),
        .aes_address_o(aes_address),
        .aes_write_data_o(aes_write_data)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_temp <= 128'd0;

        end else if (reg_operation == 0) begin
            // TODO: generate_challenge_response stuff

        end else if (reg_operation == 1) begin
            // TODO: verify_id stuff

        end
    end

    always_comb begin
        reg_operation = operation;
    end

endmodule
