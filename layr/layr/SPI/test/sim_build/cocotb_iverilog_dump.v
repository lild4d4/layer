module cocotb_iverilog_dump();
initial begin
    string dumpfile_path;    if ($value$plusargs("dumpfile_path=%s", dumpfile_path)) begin
        $dumpfile(dumpfile_path);
    end else begin
        $dumpfile("/home/schlafel/hwcodesign/layer/layr/layr/SPI/test/sim_build/axi_lite_master.fst");
    end
    $dumpvars(0, axi_lite_master);
end
endmodule
