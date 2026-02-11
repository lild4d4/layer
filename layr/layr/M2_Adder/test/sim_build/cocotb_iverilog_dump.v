module cocotb_iverilog_dump();
initial begin
    string dumpfile_path;    if ($value$plusargs("dumpfile_path=%s", dumpfile_path)) begin
        $dumpfile(dumpfile_path);
    end else begin
        $dumpfile("/home/schlafel/hwcodesign/My-First-Chip-DYC26/firstdesign/M2_Adder/test/sim_build/adder.fst");
    end
    $dumpvars(0, adder);
end
endmodule
