module chip(
    input clk,
    input rst_n,
    input button,

    input [3:0] X,

    output [6:0] seg0,
    output [6:0] seg1
);

logic save_A;
logic save_B;
logic show_result;
logic [4:0] result;
logic [3:0] tens;
logic [3:0] ones;

controller u_ctrl(
    .clk(clk),
    .rst_n(rst_n),
    .button(button),
    .save_A(save_A),
    .save_B(save_B),
    .show_result(show_result)
);

adder u_adder(
    .clk(clk),
    .operand(X),
    .save_A(save_A),
    .save_B(save_B),
    .result(result)
);

bcd_converter u_bcd(
    .binary(result),
    .tens(tens),
    .ones(ones)
);

seven_segment u_seg0(
    .clk(clk),
    .digit(ones),
    .update(show_result),
    .seg(seg0)
);

seven_segment u_seg1(
    .clk(clk),
    .digit(tens),
    .update(show_result),
    .seg(seg1)
);

endmodule
