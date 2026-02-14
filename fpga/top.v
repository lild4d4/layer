module top(
    input  wire clk,
    output wire led
);

reg [23:0] counter = 0;

always @(posedge clk)
    counter <= counter + 1;

assign led = counter[23];

endmodule