module clock_divider #(
    parameter WIDTH = 11,
    parameter [WIDTH-1:0] div_num = 35
)(
    input clk,
    input rst,
    output clk_out
); 
reg [WIDTH-1:0] pos_count, neg_count;
 
always @(posedge clk)begin
    if (rst)
        pos_count <=0;
    else if (pos_count ==div_num-1)
        pos_count <= 0;
    else pos_count<= pos_count +1;
end

always @(negedge clk)begin
    if (rst)
        neg_count <=0;
    else if (neg_count == div_num-1)
        neg_count <= 0;
    else neg_count<= neg_count +1; 
end

assign clk_out = ((pos_count > (div_num>>1)) | (neg_count > (div_num>>1))); 

endmodule