// spi_top_wrapper.sv
// Thin testbench wrapper around spi_top that renames the PULP SPI signals
// to standard names so cocotbext-spi's SpiBus can connect.
//
// PULP SPI master in standard (non-quad) mode:
//   - TX on spi_sdo0  → MOSI
//   - RX on spi_sdi1  → MISO  (confirmed from spi_master_rx.sv)
//   - spi_csn1        → NFC chip select (active low)

module spi_top_wrapper #(
    parameter [7:0] SPI_CLK_DIV = 8'd2  // Fast clock for simulation
)(
    input  wire       clk,
    input  wire       rst_n,

    // ── NFC command interface ────────────────────────────────
    input  wire       nfc_cmd_valid,
    input  wire       nfc_cmd_write,
    input  wire [5:0] nfc_cmd_addr,
    input  wire [7:0] nfc_cmd_wdata,
    output wire [7:0] nfc_cmd_rdata,
    output wire       nfc_cmd_done,
    output wire       nfc_cmd_busy,

    // ── EEPROM command interface (tied off in test) ─────────
    input  wire       eeprom_cmd_valid,
    input  wire       eeprom_cmd_write,
    input  wire [6:0] eeprom_cmd_addr,
    input  wire [7:0] eeprom_cmd_wdata,
    output wire [7:0] eeprom_cmd_rdata,
    output wire       eeprom_cmd_done,
    output wire       eeprom_cmd_busy,

    // ── SPI signals with standard names for cocotbext-spi ────
    output wire       nfc_sclk,
    output wire       nfc_mosi,
    input  wire       nfc_miso,
    output wire       nfc_cs
);

    // Internal SPI wires from spi_top
    wire        spi_clk_int;
    wire        spi_csn0, spi_csn1, spi_csn2, spi_csn3;
    wire [1:0]  spi_mode;
    wire        spi_sdo0, spi_sdo1, spi_sdo2, spi_sdo3;
    wire        spi_sdi0, spi_sdi1, spi_sdi2, spi_sdi3;

    // Map standard names to PULP signals
    assign nfc_sclk = spi_clk_int;
    assign nfc_mosi = spi_sdo0;        // PULP TX standard mode → sdo0
    assign nfc_cs   = spi_csn1;        // NFC uses CS1

    // MISO → sdi1 (PULP RX standard mode samples sdi1)
    assign spi_sdi0 = 1'b0;
    assign spi_sdi1 = nfc_miso;
    assign spi_sdi2 = 1'b0;
    assign spi_sdi3 = 1'b0;

    spi_top #(
        .SPI_CLK_DIV (SPI_CLK_DIV)
    ) u_spi_top (
        .clk              (clk),
        .rst_n            (rst_n),

        // EEPROM interface
        .eeprom_cmd_valid (eeprom_cmd_valid),
        .eeprom_cmd_write (eeprom_cmd_write),
        .eeprom_cmd_addr  (eeprom_cmd_addr),
        .eeprom_cmd_wdata (eeprom_cmd_wdata),
        .eeprom_cmd_rdata (eeprom_cmd_rdata),
        .eeprom_cmd_done  (eeprom_cmd_done),
        .eeprom_cmd_busy  (eeprom_cmd_busy),

        // NFC interface
        .nfc_cmd_valid    (nfc_cmd_valid),
        .nfc_cmd_write    (nfc_cmd_write),
        .nfc_cmd_addr     (nfc_cmd_addr),
        .nfc_cmd_wdata    (nfc_cmd_wdata),
        .nfc_cmd_rdata    (nfc_cmd_rdata),
        .nfc_cmd_done     (nfc_cmd_done),
        .nfc_cmd_busy     (nfc_cmd_busy),

        // SPI physical pins
        .spi_clk  (spi_clk_int),
        .spi_csn0 (spi_csn0),
        .spi_csn1 (spi_csn1),
        .spi_csn2 (spi_csn2),
        .spi_csn3 (spi_csn3),
        .spi_mode (spi_mode),
        .spi_sdo0 (spi_sdo0),
        .spi_sdo1 (spi_sdo1),
        .spi_sdo2 (spi_sdo2),
        .spi_sdo3 (spi_sdo3),
        .spi_sdi0 (spi_sdi0),
        .spi_sdi1 (spi_sdi1),
        .spi_sdi2 (spi_sdi2),
        .spi_sdi3 (spi_sdi3)
    );

endmodule
