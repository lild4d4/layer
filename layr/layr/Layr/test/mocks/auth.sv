module auth(
    //--------------------------------------
    // = Required =
    //--------------------------------------
    input wire clk,
    input wire rst,

    //--------------------------------------
    // = Control =
    //
    // operation_i:
    //   0 = Generate challenge response
    //   1 = Verify ID
    //
    // start_i:
    //   0 = Do nothing
    //   1 = Run selected operation with
    //       data_i as input.
    //--------------------------------------
    input wire operation_i,
    input wire start_i,

    //--------------------------------------
    // = Data bus =
    //
    // data_i:
    //   Input data for any selected operation.
    //
    // data_o:
    //   Output data for any selected operation.
    //
    // valid_o:
    //   0 = the operation is still running
    //   1 = the operation is done, data
    //       can be read from data_o
    //--------------------------------------
    input reg [127:0] data_i,
    output reg [127:0] data_o,
    output logic valid_o
);
    logic [7:0] ctr;
    logic reg_operation;
    logic start;

    always_ff @(posedge clk) begin
        if(start_i & ~start & ~valid_o) begin
            reg_operation <= operation_i;
            ctr <= 8'h05;
            start <= 1;
            if (operation_i == 0) begin
                data_o <= data_i + 'd42;
            end else if (operation_i == 1) begin
                if(data_i == 'd42)
                    // test input is valid if 42
                    data_o <= '1;
                else
                    data_o <= 0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_o <= 0;
            reg_operation <= 0;
            data_o <= 0;
            ctr <= 8'h05;
            start <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if(ctr >= 0 & ctr <= 'h05 & start)
            ctr <= ctr-1;
        if(ctr == 0 & start)begin
            valid_o <= 1;
            start <= 0;
        end

        if(~start)
            valid_o <= 0;
    end

endmodule
 