module auth_init(
    input logic clk,
    input logic rst,
    input logic start_i, // manually trigger init process, has to be active during posedge of clk

    output reg aes_cs_o,
    output reg aes_we_o,
    output reg [7:0] aes_address_o,
    output reg [31:0] aes_write_data_o
);

    enum {
        IDLE,
        FETCH,
        CONFIG
    } current_state, next_state;

    reg key_loaded; // TODO: Handle key_loaded = 1 state (Skip FETCH state)
    reg [31:0] reg_key [0:7]; // Store key locally after first init, so external connection to EEPROM is only necessary once.
    reg [2:0] key_index;

    always_ff @(posedge clk or posedge rst) begin
        if (rst || start_i) begin
            current_state <= FETCH;
            key_index <= 4'd0;
            key_loaded <= 1'b0;
            aes_cs_o <= 1'b0;
            aes_we_o <= 1'b0;
            aes_address_o <= 8'b0;
            aes_write_data_o <= 32'b0;

        end else if (current_state == FETCH) begin
            if (key_index == 4'd3) begin
                key_index <= 4'd0;
                current_state <= CONFIG;

            end else begin
                key_index <= key_index + 4'd1;
            end

        // Handle key index while writing key to aes core.
        end else if (current_state == CONFIG) begin
            if (key_index == 4'd3) begin
                key_index <= 4'd0;
                aes_cs_o = 1'b0;
                aes_we_o = 1'b0;
                aes_address_o <= 8'b0;
                aes_write_data_o <= 32'b0;
                current_state <= IDLE;

            end else begin
                key_index <= key_index + 4'd1;
            end

        end else begin
            key_index <= 4'd0;
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE: begin
                next_state = IDLE;
            end

            FETCH: begin
                // TODO: Get key from EEPROM, prolly not possible in one cycle.
                // Only change state to config after key has been loaded.
                // TODO: Keep in mind that key index 0 is the most significant
                // portion of the key.
                reg_key[key_index] = 32'd10 + key_index;
            end

            CONFIG: begin
                //  Key addresses (32 bit write bus):
                //      start: 8'h10
                //      end:   8'h17
                aes_address_o = 8'h10 + key_index;
                aes_write_data_o = reg_key[key_index];
                aes_we_o = 1'b1;
                aes_cs_o = 1'b1;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
