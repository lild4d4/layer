module controller(
    input logic clk,
    input logic rst_n,
    input logic button,

    output logic save_A,
    output logic save_B,
    output logic show_result
);

enum { WAIT_A, WAIT_B, SHOW_RESULT} state, next_state;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
         state <= WAIT_A;
    end
    else begin
        state <= next_state;
    end
end

always_comb begin
    save_A = 0;
    save_B = 0;
    show_result = 0;
    next_state = state;

    case (state)
        WAIT_A: if (button) begin
            save_A = 1;
            next_state = WAIT_B;
        end
        WAIT_B: if (button) begin
            save_B = 1;
            next_state = SHOW_RESULT;
        end
        SHOW_RESULT: if (button) begin
            show_result = 1;
            next_state = WAIT_A;
        end
        default: next_state = WAIT_A;
    endcase
end

endmodule