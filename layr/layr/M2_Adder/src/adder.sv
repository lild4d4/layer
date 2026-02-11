module adder(
    input clk,
    input [3:0] operand,
    input save_A,
    input save_B,
    output [4:0] result
);

logic [3:0] A;
logic [3:0] B;

always_ff @(posedge clk) begin
    if (save_A) A <= operand;
    if (save_B) B <= operand;
end

assign result = A + B;

endmodule
