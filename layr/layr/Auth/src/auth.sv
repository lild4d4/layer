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
    reg aes_cs;
    reg aes_we;
    reg [7:0] aes_address;
    reg [31:0] aes_write_data;
    wire [31:0] aes_read_data;
    wire [127:0] reg_data_i;

    // auth_init connections
    wire auth_init_done;
    wire auth_init_start_i;
    wire auth_init_aes_cs;
    wire auth_init_aes_we;
    wire [7:0] auth_init_aes_address;
    wire [31:0] auth_init_aes_write_data;

    // auth_generate_challenge
    wire generate_challenge_error;
    wire auth_generate_challenge_aes_cs;
    wire auth_generate_challenge_aes_we;
    wire [7:0] auth_generate_challenge_aes_address;
    wire [31:0] auth_generate_challenge_aes_write_data;

    // auth_verify_id
    wire verify_id_error;
    wire auth_verify_id_aes_cs;
    wire auth_verify_id_aes_we;
    wire [7:0] auth_verify_id_aes_address;
    wire [31:0] auth_verify_id_aes_write_data;

    // misc
    reg reg_operation;
    reg generate_challenge_valid;
    reg id_valid;
    reg reg_start;

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
        .init_done(auth_init_done),
        .aes_cs_o(auth_init_aes_cs),
        .aes_we_o(auth_init_aes_we),
        .aes_address_o(auth_init_aes_address),
        .aes_write_data_o(auth_init_aes_write_data)
    );

    auth_generate_challenge generate_challenge(
        .clk(clk),
        .rst(rst),

        // Inputs
        .ready_i(!reg_operation),
        .input_cipher_i(reg_data_i),
        .aes_read_data_i(aes_read_data),

        // Outputs
        .error_o(generate_challenge_error),
        .challenge_valid_o(generate_challenge_valid),
        .challenge_response_o(data_o),
        .aes_cs_o(auth_generate_challenge_aes_cs),
        .aes_we_o(auth_generate_challenge_aes_we),
        .aes_address_o(auth_generate_challenge_aes_address),
        .aes_write_data_o(auth_generate_challenge_aes_write_data)
    );

    auth_verify_id verify_id(
        .clk(clk),
        .rst(rst),

        // Inputs
        .ready_i(reg_operation),
        .id_cipher_i(reg_data_i),

        // Outputs
        .error_o(verify_id_error),
        .success_o(id_valid),
        .aes_cs_o(auth_verify_id_aes_cs),
        .aes_we_o(auth_verify_id_aes_we),
        .aes_address_o(auth_verify_id_aes_address),
        .aes_write_data_o(auth_verify_id_aes_write_data)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            aes_cs <= 1'b0;
            aes_we <= 1'b0;
            reg_start <= 1'b0;
            reg_operation <= 1'b0;

        end else if (!auth_init_done || reg_start == 0) begin
            aes_cs <= auth_init_aes_cs;
            aes_we <= auth_init_aes_we;
            aes_address <= auth_init_aes_address;
            aes_write_data <= auth_init_aes_write_data;

        end else if (reg_operation == 0) begin
            aes_cs <= auth_generate_challenge_aes_cs;
            aes_we <= auth_generate_challenge_aes_we;
            aes_address <= auth_generate_challenge_aes_address;
            aes_write_data <= auth_generate_challenge_aes_write_data;

        end else if (reg_operation == 1) begin
            aes_cs <= auth_verify_id_aes_cs;
            aes_we <= auth_verify_id_aes_we;
            aes_address <= auth_verify_id_aes_address;
            aes_write_data <= auth_verify_id_aes_write_data;

        end
    end

    always_comb begin
        reg_operation = operation_i;
        reg_start = start_i;
    end

endmodule
