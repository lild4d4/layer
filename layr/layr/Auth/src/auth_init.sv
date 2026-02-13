module auth_init(
    input logic clk,
    input logic rst,
    input logic start_i, // manually trigger init process, has to be active during posedge of clk

    output logic        aes_cs_o,
    output logic        aes_we_o,
    output logic [7:0]  aes_address_o,
    output logic [31:0] aes_write_data_o
);
    localparam AES_CORE_KEY_ADDR = 8'h14;

    enum {
        IDLE,
        FETCH,
        CONFIG
    } state, next_state;

    logic        key_loaded, next_key_loaded;
    logic [1:0]  key_index, next_key_index;
    logic [31:0] reg_key [0:3];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= FETCH;
            key_index       <= 2'd0;
            key_loaded      <= 1'b0;
            aes_cs_o        <= 1'b0;
            aes_we_o        <= 1'b0;
            aes_address_o   <= AES_CORE_KEY_ADDR;
            aes_write_data_o<= 32'b0;

            foreach (reg_key[i]) begin
                reg_key[i] <= 32'd0;
            end
        end else begin
            state           <= next_state;
            key_index       <= next_key_index;
            key_loaded      <= next_key_loaded;
            aes_cs_o        <= (next_state == CONFIG);
            aes_we_o        <= (next_state == CONFIG);
            aes_address_o   <= AES_CORE_KEY_ADDR + next_key_index;
            aes_write_data_o<= reg_key[next_key_index];
        end
    end

    always_comb begin
        next_state      = state;
        next_key_index  = key_index;
        next_key_loaded = key_loaded;

        if (start_i) begin
            next_state      = FETCH;
            next_key_index  = 2'd0;
            next_key_loaded = 1'b0;
        end

        case (state)
            IDLE: ;

            FETCH: begin
                reg_key[key_index] = 32'd10 + key_index; //TODO: Read from EEPROM
                if (key_index == 2'd3) begin
                    next_key_loaded = 1'b1;
                    next_state      = CONFIG;
                end
                next_key_index = key_index + 2'd1;
            end

            CONFIG: begin
                if (key_index == 2'd3) begin
                    next_state      = IDLE;
                    next_key_index  = 2'd0;
                end else begin
                    next_key_index = key_index + 2'd1;
                end
            end

            default: ;
        endcase
    end
endmodule
