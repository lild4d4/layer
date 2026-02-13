module auth_generate_challenge(
    input logic clk,
    input logic rst,
    input logic ready_i,
    input logic [127:0] input_cipher_i,
    input reg [31:0] aes_read_data_i,

    output logic error_o,
    output logic challenge_valid_o,
    output logic [127:0] challenge_response_o,
    output reg aes_cs_o,
    output reg aes_we_o,
    output reg [7:0] aes_address_o,
    output reg [31:0] aes_write_data_o
);
    enum {
        IDLE,
        READ_CHAL,
        DECRYPT,
        GET_RNG,
        ENCRYPT,
        SEND
    } current_state, next_state;

    enum {
        DECRYPT_SET_MODE,
        DECRYPT_WRITE,
        DECRYPT_INIT,
        DECRYPT_NEXT,
        DECRYPT_WAIT,
        DECRYPT_DONE
    } decrypt_current_state, decrypt_next_state;

    enum {
        ENCRYPT_SET_MODE,
        ENCRYPT_WRITE_CR,
        ENCRYPT_READ_CR,
        ENCRYPT_WRITE_SK,
        ENCRYPT_READ_SK,
        ENCRYPT_RUN
    } encrypt_current_state, encrypt_next_state;

    reg decrypt_done;
    reg [2:0] key_index;
    reg [2:0] data_index;
    reg [127:0] reg_input_chiper;
    reg [64:0] rc;
    reg [64:0] rt;

    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE: begin
                if (ready_i) next_state = READ_CHAL;
            end

            READ_CHAL: begin
                next_state = DECRYPT;
            end

            DECRYPT: begin
                // TODO
                case (decrypt_current_state)
                    DECRYPT_SET_MODE: decrypt_next_state = DECRYPT_WRITE;
                    DECRYPT_WRITE: ; // TODO, need to wait until writing is done
                    DECRYPT_INIT: decrypt_next_state = DECRYPT_NEXT;
                    DECRYPT_NEXT: decrypt_next_state = DECRYPT_WAIT;
                    DECRYPT_WAIT: begin
                        if (decrypt_done) begin
                            decrypt_next_state = DECRYPT_DONE;
                        end
                    end
                    DECRYPT_DONE: ; // TODO, need to read results
                    default: decrypt_next_state = DECRYPT_SET_MODE;
                endcase
            end

            GET_RNG: begin
                // TODO
            end

            ENCRYPT: begin
                // TODO
            end

            SEND: begin
                // TODO
            end

            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        aes_cs_o <= 1'b0;
        aes_we_o <= 1'b0;
        aes_address_o <= 8'd0;
        aes_write_data_o <= 32'd0;

        case (next_state)
            //----------------------------
            // READ_CHAL
            //----------------------------
            READ_CHAL: begin
            end

            //----------------------------
            // DECRYPT
            //----------------------------
            DECRYPT: begin
                case (decrypt_next_state)
                    DECRYPT_SET_MODE: begin // 128 bit ECB decrypt
                        aes_cs_o <= 1'b1;
                        aes_we_o <= 1'b1;
                        aes_address_o <= 8'h0a;
                        aes_write_data_o <= 31'h1;
                    end

                    DECRYPT_WRITE: begin
                        aes_cs_o <= 1'b1;
                        aes_we_o <= 1'b1;
                        aes_address_o <= 8'h20 + data_index;
                        aes_write_data_o <= reg_input_chiper[127 - data_index*32 -: 32];
                    end

                    DECRYPT_INIT: begin
                        aes_cs_o <= 1'b1;
                        aes_we_o <= 1'b1;
                        aes_address_o <= 8'h08;
                        aes_write_data_o <=32'h1;
                    end

                    DECRYPT_NEXT: begin
                        aes_cs_o <= 1'b1;
                        aes_we_o <= 1'b1;
                        aes_address_o <= 8'h08;
                        aes_write_data_o <=32'h2;
                    end

                    DECRYPT_WAIT: begin
                        aes_cs_o <= 1'b1;
                        aes_we_o <= 1'b0;
                        aes_address_o <= 8'h09;
                    end

                    DECRYPT_DONE: begin
                    end

                    default: ;
                endcase
            end

            //----------------------------
            // GET_RNG
            //----------------------------
            GET_RNG: begin
            end

            //----------------------------
            // ENCRYPT
            //----------------------------
            ENCRYPT: begin
            end

            //----------------------------
            // SEND
            //----------------------------
            SEND: begin
            end
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            decrypt_done <= 1'b0;
            // TODO: Reset module
        end else begin
            current_state <= next_state;
            decrypt_current_state <= decrypt_next_state;
            encrypt_current_state <= encrypt_next_state;

            if ((current_state == DECRYPT && decrypt_current_state == DECRYPT_WRITE) ||
                (current_state == ENCRYPT && encrypt_current_state == ENCRYPT_WRITE)) begin
                if (data_index == 3'd3) begin
                    data_index <= 3'd0;
                end else begin
                    data_index = data_index + 3'd1;
                end
            end

            if (current_state == DECRYPT && decrypt_current_state == DECRYPT_WAIT) begin
                decrypt_done <= aes_read_data_i[1];
            end
        end
    end


    // TODO: set ecb 128 bit decrypt mode for aes core, key is already set

    // TODO: Write input challenge to aes core input

    // TODO: set init bit for aes core
    /*
    cs          = 1'b1;
    we          = 1'b1;
    address     = 8'h08;
    write_data  = 32'h1;
    */
    // TODO: decrypt reg_input_chiper (AES ECB)
    // TODO: obtain rc
    // TODO: get random value rt (NFC reader apparently has RNG)
    // TODO: set ecb 128 bit encrypt mode for aes core, key is already set
    /*
    cs = 1'b1;
    we = 1'b1;
    aes_address = 8'h0a;
    write_data = 32'h0;
    */
    // TODO: set init bit for aes core
    /*
    cs          = 1'b1;
    we          = 1'b1;
    address     = 8'h08;
    write_data  = 32'h1;
    * */
    // TODO: create AES_psk(rt || rc)
    // TODO: send AES_psk(rt || rc) to auth_verify_id
    // TODO: store AES_psk(rt || rc) in reg_challenge_response

endmodule
