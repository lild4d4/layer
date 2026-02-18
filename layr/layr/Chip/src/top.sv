module top (
`ifdef USE_POWER_PINS
    inout wire IOVDD,
    inout wire IOVSS,
    inout wire VDD,
    inout wire VSS,
`endif

    inout rst_PAD,
    inout clk_PAD,

    inout cs_1_PAD,
    inout cs_0_PAD,
    inout spi_sclk_PAD,
    inout spi_mosi_PAD,
    inout spi_miso_PAD,
    inout status_fault_PAD,
    inout status_unlock_PAD,
    inout status_busy_PAD
);

  logic clk;
  logic rst;

  // Power/ground pad instances
  generate
    for (genvar i = 0; i < 1; i++) begin : iovdd_pads
      (* keep *)
      sg13g2_IOPadIOVdd iovdd_pad (
`ifdef USE_POWER_PINS
          .iovdd(IOVDD),
          .iovss(IOVSS),
          .vdd  (VDD),
          .vss  (VSS)
`endif
      );
    end
    for (genvar i = 0; i < 1; i++) begin : iovss_pads
      (* keep *)
      sg13g2_IOPadIOVss iovss_pad (
`ifdef USE_POWER_PINS
          .iovdd(IOVDD),
          .iovss(IOVSS),
          .vdd  (VDD),
          .vss  (VSS)
`endif
      );
    end
    for (genvar i = 0; i < 1; i++) begin : vdd_pads
      (* keep *)
      sg13g2_IOPadVdd vdd_pad (
`ifdef USE_POWER_PINS
          .iovdd(IOVDD),
          .iovss(IOVSS),
          .vdd  (VDD),
          .vss  (VSS)
`endif
      );
    end
    for (genvar i = 0; i < 1; i++) begin : vss_pads
      (* keep *)
      sg13g2_IOPadVss vss_pad (
`ifdef USE_POWER_PINS
          .iovdd(IOVDD),
          .iovss(IOVSS),
          .vdd  (VDD),
          .vss  (VSS)
`endif
      );
    end
  endgenerate

  // rst PAD instance (Pin1)
  sg13g2_IOPadIn rst_pad (
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .p2c  (rst),
      .pad  (rst_PAD)
  );

  // clk PAD instance (Pin2)
  sg13g2_IOPadIn clk_pad (
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .p2c  (clk),
      .pad  (clk_PAD)
  );

  // SPI signals
  logic spi_sclk;
  logic spi_mosi;
  logic spi_miso;
  logic cs_0;
  logic cs_1;
  logic status_busy;
  logic status_fault;
  logic status_unlock;

  // cs_1 PAD (Pin13 - spi chip select 1 - AT25010B)
  sg13g2_IOPadOut4mA cs_1_pad (
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .c2p  (cs_1),
      .pad  (cs_1_PAD)
  );

  // cs_0 PAD (Pin14 - spi chip select 2 - MFRC522)
  sg13g2_IOPadOut4mA cs_0_pad (
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .c2p  (cs_0),
      .pad  (cs_0_PAD)
  );

  // spi_mosi PAD (Pin16)
  sg13g2_IOPadOut4mA spi_mosi_pad (
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .c2p  (spi_mosi),
      .pad  (spi_mosi_PAD)
  );

  // spi_sclk PAD (Pin17)
  sg13g2_IOPadOut4mA spi_sclk_pad (
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .c2p  (spi_sclk),
      .pad  (spi_sclk_PAD)
  );

  // status unlock PAD (Pin20)
  sg13g2_IOPadOut4mA status_unlock_pad(
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .c2p(status_unlock),
      .pad(status_unlock_PAD)
  );

  // status_fault PAD (Pin21)
  sg13g2_IOPadOut4mA status_fault_pad (
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .c2p(status_fault),
      .pad(status_fault_PAD)
  );

  // status_busy PAD (Pin22)
  sg13g2_IOPadOut4mA status_busy_pad (
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .c2p  (status_busy),
      .pad  (status_busy_PAD)
  );

  // spi_miso PAD (Pin15 - input)
  sg13g2_IOPadIn spi_miso_pad (
`ifdef USE_POWER_PINS
      .iovdd(IOVDD),
      .iovss(IOVSS),
      .vdd  (VDD),
      .vss  (VSS),
`endif
      .p2c  (spi_miso),
      .pad  (spi_miso_PAD)
  );

  chip u_chip (
      .clk(clk),
      .rst(rst),

      .spi_sclk(spi_sclk),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .cs_0(cs_0),
      .cs_1(cs_1),

      .status_fault(status_fault),
      .status_unlock(status_unlock),
      .status_busy(status_busy)
  );

endmodule
