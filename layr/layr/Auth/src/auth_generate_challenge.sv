module auth_generate_challenge(
    /*
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
    */
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
        IDLE,
        READ_CHAL,
        DECRYPT,
        GET_RNG,
        ENCRYPT,
        SEND
    } cur_top_st, nxt_top_st;

    enum {
        /*
        DECRYPT_SET_MODE,
        DECRYPT_WRITE,
        DECRYPT_INIT,
        DECRYPT_NEXT,
        DECRYPT_WAIT,
        DECRYPT_DONE
        */
        D_IDLE,          // safe entry point (used only internally)
        D_SET_MODE,      // write mode register (0x0A, value = 1)
        D_WRITE_BLOCK,   // feed 128‑bit ciphertext (8 words)
        D_INIT,          // write init bit (0x08, value = 1)
        D_NEXT,          // write next command (0x08, value = 2)
        D_WAIT,          // poll status register (0x09, read)
        D_DONE           // read decrypted block (0x30)
    } d_cur_st, d_nxt_st;

    enum {
        ENCRYPT_SET_MODE,
        ENCRYPT_WRITE_CR,
        ENCRYPT_READ_CR,
        ENCRYPT_WRITE_SK,
        ENCRYPT_READ_SK,
        ENCRYPT_RUN
    } encrypt_current_state, encrypt_next_state;

    /*
    reg decrypt_aes_core_done;
    reg decrypt_read;
    reg [2:0] key_index;
    reg [2:0] data_index;
    reg [2:0] plain_index;
    reg [127:0] reg_input_chiper;
    reg [63:0] rc;
    reg [63:0] rt;
    */

    logic [127:0]  reg_input_chiper;   // latched ciphertext
    logic [2:0]    data_idx;           // 0‑7 word index
    logic [2:0]    plain_idx;          // 0‑3 index for assembling rc
    logic          decrypt_aes_core_done;
    logic          decrypt_read;       // indicates we have collected rc
    logic [63:0]   rc;                 // recovered random value (part of PSK)

    always_comb begin : TOP_FSM_COMB
        nxt_top_st = cur_top_st;
        case (cur_top_st)
            IDLE: if (ready_i) nxt_top_st = READ_CHAL;
            READ_CHAL: nxt_top_st = DECRYPT;
            DECRYPT: if (d_cur_st == D_DONE) nxt_top_st = GET_RNG;
            GET_RNG:    /* TODO – stay here until RNG ready */ ;
            ENCRYPT:   /* TODO */ ;
            SEND:      /* TODO */ ;
            default:    nxt_top_st = IDLE;
        endcase
    end

    always_comb begin : DECRYPT_FSM_COMB
        // Default: stay in the current state
        d_nxt_st = d_cur_st;

        // The decrypt FSM is only active when the top‑level state is DECRYPT
        if (cur_top_st != DECRYPT) begin
            d_nxt_st = D_IDLE;
        end else begin
            case (d_cur_st)
                D_IDLE: begin
                    // First thing we must do is select ECB‑decrypt mode
                    d_nxt_st = D_SET_MODE;
                end

                D_SET_MODE: begin
                    // After setting the mode we start feeding the ciphertext
                    d_nxt_st = D_WRITE_BLOCK;
                end

                D_WRITE_BLOCK: begin
                    // When the last word (index 7) has been written we move on
                    if (data_idx == 3'd7) d_nxt_st = D_INIT;
                end

                D_INIT: begin
                    // Init command issued – next we tell the core to go to the next block
                    d_nxt_st = D_NEXT;
                end

                D_NEXT: begin
                    // After issuing NEXT we wait for the core to finish
                    d_nxt_st = D_WAIT;
                end

                D_WAIT: begin
                    // Core signals completion via aes_read_data_i[1]
                    if (decrypt_aes_core_done) d_nxt_st = D_DONE;
                end

                D_DONE: begin
                    // Once we have read the decrypted block we are finished
                    d_nxt_st = D_IDLE;   // will cause top‑level FSM to advance
                end

                default: d_nxt_st = D_IDLE;
            endcase
        end
    end

    always_comb begin : AES_CTRL_COMB
        // Default (nothing active)
        aes_cs_o        = 1'b0;
        aes_we_o        = 1'b0;
        aes_address_o   = 8'd0;
        aes_write_data_o= 32'd0;

        // Only drive the core while we are in the DECRYPT top‑level state
        if (cur_top_st == DECRYPT) begin
            case (d_nxt_st)                     // use *next* state for immediate effect
                D_SET_MODE: begin
                    aes_cs_o        = 1'b1;
                    aes_we_o        = 1'b1;
                    aes_address_o   = 8'h0A;          // mode register
                    aes_write_data_o= 32'h1;          // ECB‑decrypt
                end

                D_WRITE_BLOCK: begin
                    aes_cs_o        = 1'b1;
                    aes_we_o        = 1'b1;
                    aes_address_o   = 8'h24 + data_idx;   // data registers 0‑7
                    // Slice the appropriate 32‑bit word from the 128‑bit ciphertext
                    aes_write_data_o= reg_input_chiper[127 - data_idx*32 -: 32];
                end

                D_INIT: begin
                    aes_cs_o        = 1'b1;
                    aes_we_o        = 1'b1;
                    aes_address_o   = 8'h08;          // init register
                    aes_write_data_o= 32'h1;
                end

                D_NEXT: begin
                    aes_cs_o        = 1'b1;
                    aes_we_o        = 1'b1;
                    aes_address_o   = 8'h08;          // same register, different command
                    aes_write_data_o= 32'h2;
                end

                D_WAIT: begin
                    aes_cs_o        = 1'b1;
                    aes_we_o        = 1'b0;           // read‑only
                    aes_address_o   = 8'h09;          // status register
                end

                D_DONE: begin
                    aes_cs_o        = 1'b1;
                    aes_we_o        = 1'b0;
                    aes_address_o   = 8'h30;          // read decrypted block
                end

                default: ; // keep everything low
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // ----- Global reset -----
            cur_top_st          <= IDLE;
            d_cur_st            <= D_IDLE;
            reg_input_chiper    <= 128'd0;
            data_idx            <= 3'd0;
            plain_idx           <= 3'd0;
            rc                  <= 64'd0;
            decrypt_aes_core_done <= 1'b0;
            decrypt_read        <= 1'b0;
        end else begin
            // ----- Top‑level FSM state register -----
            cur_top_st          <= nxt_top_st;

            // ----- Decrypt FSM state register -----
            d_cur_st            <= d_nxt_st;

            // ----- Capture the incoming challenge (once) -----
            if (cur_top_st == READ_CHAL) begin
                reg_input_chiper <= input_cipher_i;
            end

            // ----- Data‑word index handling (write‑phase) -----
            if (cur_top_st == DECRYPT) begin
                // Increment only while we are feeding the eight words
                if (d_cur_st == D_WRITE_BLOCK) begin
                    if (data_idx == 3'd7)
                        data_idx <= 3'd0;          // wrap after the last word
                    else
                        data_idx <= data_idx + 3'd1;
                end
            end else begin
                data_idx <= 3'd0;                  // keep it at zero outside DECRYPT
            end

            // ----- Wait‑state: capture core‑done flag -----
            if (d_cur_st == D_WAIT) begin
                decrypt_aes_core_done <= aes_read_data_i[1]; // status bit from core
            end else begin
                decrypt_aes_core_done <= 1'b0;
            end

            // ----- Assemble the recovered random value (rc) -----
            if (d_cur_st == D_DONE) begin
                case (plain_idx)
                    3'd0: rc[63:32] <= aes_read_data_i; // first half
                    3'd1: rc[31:0]  <= aes_read_data_i; // second half
                    3'd2: ;                               // (skip – placeholder)
                    3'd3: decrypt_read <= 1'b1;           // indicate we have rc
                    default: ;
                endcase
                plain_idx <= plain_idx + 3'd1;
            end else begin
                plain_idx   <= 3'd0;
                decrypt_read<= 1'b0;
            end
        end
    end

    // TODO: Placeholder assignments
    assign error_o              = 1'b0;
    assign challenge_valid_o    = 1'b0;
    assign challenge_response_o = 128'd0;

    /*
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
                case (decrypt_current_state)
                    DECRYPT_SET_MODE: decrypt_next_state = DECRYPT_WRITE;
                    DECRYPT_WRITE: begin
                        if (data_index == 3'd7) decrypt_next_state = DECRYPT_NEXT;
                    end
                    DECRYPT_INIT: decrypt_next_state = DECRYPT_NEXT;
                    DECRYPT_NEXT: decrypt_next_state = DECRYPT_WAIT;
                    DECRYPT_WAIT: begin
                        if (decrypt_aes_core_done) begin
                            decrypt_next_state = DECRYPT_DONE;
                        end
                    end
                    DECRYPT_DONE: begin
                        if (decrypt_read) begin
                            decrypt_next_state = DECRYPT_SET_MODE;
                            next_state = GET_RNG;
                        end
                    end
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
    */

    /*
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
                reg_input_chiper <= input_cipher_i;
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
                        aes_address_o <= 8'h24 + data_index;
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
                        aes_cs_o <= 1'b1;
                        aes_we_o <= 1'b0;
                        aes_address_o <= 8'h30;
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
    */

    /*
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_input_chiper <= 128'd0;
            decrypt_aes_core_done <= 1'b0;
            decrypt_read <= 1'b0;
            plain_index <= 1'b0;
            data_index <= 1'b0;
            rc <= 64'd0;

        end else begin
            current_state <= next_state;
            decrypt_current_state <= decrypt_next_state;
            encrypt_current_state <= encrypt_next_state;

            if ((current_state == DECRYPT && decrypt_current_state == DECRYPT_WRITE) ||
                (current_state == ENCRYPT && encrypt_current_state == ENCRYPT_WRITE_CR) ||
                (current_state == ENCRYPT && encrypt_current_state == ENCRYPT_WRITE_SK)) begin
                if (data_index == 3'd7) begin
                    data_index <= 3'd0;
                end else begin
                    data_index = data_index + 3'd1;
                end

            end else if (current_state == DECRYPT && decrypt_current_state == DECRYPT_WAIT) begin
                decrypt_aes_core_done <= aes_read_data_i[1];
                data_index <= 3'd0;

            end else if (current_state == DECRYPT && decrypt_current_state == DECRYPT_DONE) begin
                case (plain_index)
                    3'd0: rc[63:32] <= aes_read_data_i;
                    3'd1: rc[31:0] <= aes_read_data_i;
                    3'd2: ; // skip
                    3'd3: decrypt_read <= 1'b1;
                endcase

                plain_index <= plain_index + 3'd1;

            end else begin
                plain_index <= 3'd0;
                decrypt_read <= 1'b0;
            end
        end
    end
    */


    // TODO: Write input challenge to aes core input

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
