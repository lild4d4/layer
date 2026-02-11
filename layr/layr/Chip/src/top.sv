module top(
    `ifdef USE_POWER_PINS
    inout wire IOVDD,
    inout wire IOVSS,
    inout wire VDD,
    inout wire VSS,
    `endif

    inout clk_PAD,
    inout rst_n_PAD,
    inout button_PAD,
    inout [3:0] X_PADs,

    output [6:0] seg0_PADs,
    output [6:0] seg1_PADs
);

logic clk;
logic rst_n;
logic button;
logic [3:0] X;
logic [6:0] seg0;
logic [6:0] seg1;
// Power/ground pad instances
generate
for (genvar i=0; i<1; i++) begin : iovdd_pads
    (* keep *)
    sg13g2_IOPadIOVdd iovdd_pad  (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS)
        `endif
    );
end
for (genvar i=0; i<1; i++) begin : iovss_pads
    (* keep *)
    sg13g2_IOPadIOVss iovss_pad  (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS)
        `endif
    );
end
for (genvar i=0; i<1; i++) begin : vdd_pads
    (* keep *)
    sg13g2_IOPadVdd vdd_pad  (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS)
        `endif
    );
end
for (genvar i=0; i<1; i++) begin : vss_pads
    (* keep *)
    sg13g2_IOPadVss vss_pad  (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS)
        `endif
    );
end
endgenerate
// clk PAD instance
sg13g2_IOPadIn clk_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .p2c    (clk),
    .pad    (clk_PAD)
);
//reset PAD instance
sg13g2_IOPadIn rst_n_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .p2c    (rst_n),
    .pad    (rst_n_PAD)
);
//X inputs PAD instance
generate
for (genvar i=0; i<4; i++) begin : x_pads
    sg13g2_IOPadIn x_pad (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS),
        `endif
        .p2c    (X[i]),
        .pad    (X_PADs[i])
    );
end
endgenerate
//Button input PAD instance
sg13g2_IOPadIn button_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .p2c    (button),
    .pad    (button_PAD)
);
//Outputs PADs
generate
for (genvar i=0; i<7; i++) begin : seg0_pads
    sg13g2_IOPadOut30mA seg0_pad (
        `ifdef USE_POWER_PINS
        .vss    (VSS),
        .vdd    (VDD),
        .iovss  (IOVSS),
        .iovdd  (IOVDD),
        `endif
        .c2p (seg0[i]),
        .pad (seg0_PADs[i])
    );
end
endgenerate
generate
for (genvar i=0; i<7; i++) begin : seg1_pads
    sg13g2_IOPadOut30mA seg1_pad (
        `ifdef USE_POWER_PINS
        .vss    (VSS),
        .vdd    (VDD),
        .iovss  (IOVSS),
        .iovdd  (IOVDD),
        `endif
        .c2p (seg1[i]),
        .pad (seg1_PADs[i])
    );
end
endgenerate
chip u_chip (
    .clk(clk),
    .rst_n(rst_n),
    .button(button),
    .X(X),
    .seg0(seg0),
    .seg1(seg1)
);

endmodule