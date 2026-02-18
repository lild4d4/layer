// Based on LFSR 64.
// Combines clk cycles since last rst and random input value rc as random
// factors, only returns valid after seed has been loaded and 16 64 bits have
// been shifted.
module auth_random(
    input logic clk,
    input logic rst,
    input logic load,
    input reg [63:0] seed,

    output reg [63:0] rnd,
    output logic valid,
    output logic ready
);

logic busy;
logic [4:0] counter;
logic [63:0] state;

assign rnd = state;

function automatic logic [63:0] multi_shift(input logic [63:0] s);
    logic fb0, fb1, fb2, fb3;
    fb0 = s[63] ^ s[3] ^ s[2] ^ s[0];
    fb1 = s[62] ^ s[2] ^ s[1] ^ fb0;
    fb2 = s[61] ^ s[1] ^ s[0] ^ fb1;
    fb3 = s[60] ^ s[0] ^ fb2 ^ fb1;

    multi_shift = {
        s[59:0], fb0, fb1, fb2, fb3
    };
endfunction

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= 64'h1;
        valid <= 1'b0;
        ready <= 1'b1;
        busy <= 1'b0;
        counter <= 5'b0;
    end else if (load) begin
        ready <= 1'b0;
        valid <= 1'b0;
        busy <= 1'b1;
        counter <= 5'b0;
        state <= seed ^ state;
    end else if (counter == 5'h10) begin
        valid <= 1'b1 & busy;
        ready <= 1'b1;
        busy <= 1'b0;
        counter <= 5'b0;
        state <= multi_shift(state);
    end else begin
        ready <= !busy;
        valid <= 1'b0;
        counter <= counter + 5'b1;
        state <= multi_shift(state);
    end
end

endmodule
