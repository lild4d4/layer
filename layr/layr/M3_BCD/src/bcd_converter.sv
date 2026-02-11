module bcd_converter(
    input logic [4:0] binary,
    output logic [3:0] tens,
    output logic [3:0] ones
);

    assign tens = binary / 10;
    assign ones = binary % 10;

endmodule