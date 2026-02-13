"""
test_mfrc522.py
End-to-end cocotb test for the NFC SPI path:

    nfc_cmd_* ports  →  nfc_spi FSM  →  arbiter  →  axi_lite_master
        →  axi_spi_master (PULP)  →  SPI wires  →  Mfrc522SpiSlave mock

Uses spi_top_wrapper as the HDL toplevel, which renames the PULP SPI
signals to standard names (sclk/mosi/miso/cs) for cocotbext-spi.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# ── Make the cocotbext-spi submodule importable ──────────────────────
_spi_ext = str(Path(__file__).resolve().parent.parent / "cocotbext-spi")
if _spi_ext not in sys.path:
    sys.path.insert(0, _spi_ext)

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotb_tools.runner import get_runner
from cocotbext.spi import SpiBus

# Local mock (same directory) — your full-featured MFRC522 model
from mock_mrfc522 import Mfrc522SpiSlave

os.environ["COCOTB_ANSI_OUTPUT"] = "1"


# ─────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────

async def setup(dut, version=0x92, uid=(0xDE, 0xAD, 0xBE, 0xEF)):
    """Reset the DUT, start the clock, attach the MFRC522 mock, and wait
    for the SPI clock-divider init FSM to finish."""

    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())  # 50 MHz

    # Tie off EEPROM interface (not used in these tests)
    dut.eeprom_cmd_valid.value = 0
    dut.eeprom_cmd_write.value = 0
    dut.eeprom_cmd_addr.value  = 0
    dut.eeprom_cmd_wdata.value = 0

    # Tie off NFC interface
    dut.nfc_cmd_valid.value = 0
    dut.nfc_cmd_write.value = 0
    dut.nfc_cmd_addr.value  = 0
    dut.nfc_cmd_wdata.value = 0

    # Assert reset
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Attach mock MFRC522 on the NFC SPI bus (CS1)
    spi_bus = SpiBus(
        entity=dut,
        prefix="nfc",
        sclk_name="sclk",
        mosi_name="mosi",
        miso_name="miso",
        cs_name="cs",
    )
    mock = Mfrc522SpiSlave(spi_bus, version=version, uid=uid)

    # Wait for spi_top's init FSM to programme the clock divider.
    # With SPI_CLK_DIV=2 the init AXI write completes in a few cycles.
    for _ in range(50):
        await RisingEdge(dut.clk)

    return mock


async def nfc_write(dut, addr: int, data: int, timeout_us: int = 500):
    """Issue a single NFC register write via the cmd interface and wait
    for cmd_done."""
    dut.nfc_cmd_addr.value  = addr & 0x3F
    dut.nfc_cmd_wdata.value = data & 0xFF
    dut.nfc_cmd_write.value = 1
    dut.nfc_cmd_valid.value = 1
    await RisingEdge(dut.clk)
    dut.nfc_cmd_valid.value = 0

    await with_timeout(RisingEdge(dut.nfc_cmd_done), timeout_us, "us")


async def nfc_read(dut, addr: int, timeout_us: int = 500) -> int:
    """Issue a single NFC register read via the cmd interface and return
    the data byte."""
    dut.nfc_cmd_addr.value  = addr & 0x3F
    dut.nfc_cmd_write.value = 0
    dut.nfc_cmd_valid.value = 1
    await RisingEdge(dut.clk)
    dut.nfc_cmd_valid.value = 0

    await with_timeout(RisingEdge(dut.nfc_cmd_done), timeout_us, "us")
    return int(dut.nfc_cmd_rdata.value)


# ─────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_read_version_register(dut):
    """Read the MFRC522 VersionReg (0x37) — should return 0x92."""
    mock = await setup(dut, version=0x92)

    result = await nfc_read(dut, Mfrc522SpiSlave.REG_VERSION)

    assert result == 0x92, f"Expected 0x92, got {result:#04x}"
    dut._log.info("✓ Read VersionReg = 0x92 OK")


@cocotb.test()
async def test_read_version_alternate(dut):
    """Instantiate the mock with version 0x91 and verify."""
    mock = await setup(dut, version=0x91)

    result = await nfc_read(dut, Mfrc522SpiSlave.REG_VERSION)
    assert result == 0x91, f"Expected 0x91, got {result:#04x}"
    dut._log.info("✓ Read VersionReg = 0x91 (alternate) OK")


@cocotb.test()
async def test_write_and_readback_generic_register(dut):
    """Write a generic register, then read it back — full round-trip."""
    mock = await setup(dut)
    test_addr = 0x14  # a generic register with no side-effects
    test_val  = 0xA5

    await nfc_write(dut, test_addr, test_val)
    assert mock._regs[test_addr] == test_val, "Mock register not updated"

    result = await nfc_read(dut, test_addr)
    assert result == test_val, f"Expected {test_val:#04x}, got {result:#04x}"
    dut._log.info(f"✓ Write 0x{test_val:02X} → read back 0x{result:02X} OK")


@cocotb.test()
async def test_command_reg_reset_default(dut):
    """CommandReg resets to 0x20 (RcvOff=1)."""
    mock = await setup(dut)

    result = await nfc_read(dut, Mfrc522SpiSlave.REG_COMMAND)
    assert result == 0x20, f"Expected reset default 0x20, got {result:#04x}"
    dut._log.info("✓ CommandReg reset default = 0x20 OK")


@cocotb.test()
async def test_fifo_write_and_read(dut):
    """Write bytes into FIFODataReg, read FIFOLevelReg, then read them back."""
    mock = await setup(dut)

    # Write 3 bytes into FIFO
    for b in [0x11, 0x22, 0x33]:
        await nfc_write(dut, Mfrc522SpiSlave.REG_FIFO_DATA, b)

    # Check FIFO level = 3
    level = await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 3, f"Expected FIFO level 3, got {level}"

    # Read back in FIFO order
    for expected in [0x11, 0x22, 0x33]:
        got = await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_DATA)
        assert got == expected, f"FIFO read: expected {expected:#04x}, got {got:#04x}"

    # FIFO should be empty now
    level = await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 0, f"Expected FIFO level 0 after drain, got {level}"
    dut._log.info("✓ FIFO write/level/read OK")


@cocotb.test()
async def test_fifo_flush(dut):
    """Writing FlushBuffer bit (0x80) to FIFOLevelReg clears the FIFO."""
    mock = await setup(dut)

    # Fill FIFO with some data
    for b in [0xAA, 0xBB, 0xCC]:
        await nfc_write(dut, Mfrc522SpiSlave.REG_FIFO_DATA, b)
    level = await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 3

    # Flush
    await nfc_write(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL, 0x80)

    level = await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 0, f"Expected FIFO level 0 after flush, got {level}"
    dut._log.info("✓ FIFO flush OK")


@cocotb.test()
async def test_soft_reset(dut):
    """Writing CMD_SOFTRESET to CommandReg resets registers to defaults."""
    mock = await setup(dut)

    # Write a known value to a generic register
    await nfc_write(dut, 0x14, 0x55)
    assert mock._regs[0x14] == 0x55

    # Soft reset
    await nfc_write(dut, Mfrc522SpiSlave.REG_COMMAND, Mfrc522SpiSlave.CMD_SOFTRESET)

    # Give the mock time to process
    await Timer(200, unit="ns")

    # Generic register should be back to 0x00
    result = await nfc_read(dut, 0x14)
    assert result == 0x00, f"Expected 0x00 after soft reset, got {result:#04x}"

    # VersionReg should still be 0x92
    result = await nfc_read(dut, Mfrc522SpiSlave.REG_VERSION)
    assert result == 0x92, f"Expected 0x92 after soft reset, got {result:#04x}"

    # IdleIRq should be set after soft reset
    irq = await nfc_read(dut, Mfrc522SpiSlave.REG_COM_IRQ)
    assert irq & Mfrc522SpiSlave.COMIRQ_IDLE, \
        f"IdleIRq should be set after soft reset, ComIrqReg={irq:#04x}"
    dut._log.info("✓ Soft reset OK")


@cocotb.test()
async def test_transceive_reqa(dut):
    """Simulate a REQA command (0x26) via Transceive and check ATQA response."""
    mock = await setup(dut)

    # 1. Flush FIFO
    await nfc_write(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL, 0x80)

    # 2. Clear IRQs
    await nfc_write(dut, Mfrc522SpiSlave.REG_COM_IRQ, 0x7F)

    # 3. Write REQA byte into FIFO
    await nfc_write(dut, Mfrc522SpiSlave.REG_FIFO_DATA, 0x26)

    # 4. Set Transceive command
    await nfc_write(dut, Mfrc522SpiSlave.REG_COMMAND, Mfrc522SpiSlave.CMD_TRANSCEIVE)

    # 5. Set StartSend (bit 7 of BitFramingReg)
    await nfc_write(dut, Mfrc522SpiSlave.REG_BIT_FRAMING, 0x80)

    # 6. Wait for mock to process (it uses a 50ns Timer internally)
    await Timer(500, unit="ns")

    # 7. Check ComIrqReg — RxIRq and IdleIRq should be set
    irq = await nfc_read(dut, Mfrc522SpiSlave.REG_COM_IRQ)
    assert irq & Mfrc522SpiSlave.COMIRQ_RX, \
        f"RxIRq not set, ComIrqReg={irq:#04x}"
    assert irq & Mfrc522SpiSlave.COMIRQ_IDLE, \
        f"IdleIRq not set, ComIrqReg={irq:#04x}"

    # 8. Read FIFO level — ATQA is 2 bytes
    level = await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 2, f"Expected FIFO level 2 (ATQA), got {level}"

    # 9. Read ATQA bytes
    atqa_0 = await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_DATA)
    atqa_1 = await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_DATA)
    assert (atqa_0, atqa_1) == (0x04, 0x00), \
        f"Expected ATQA (0x04, 0x00), got ({atqa_0:#04x}, {atqa_1:#04x})"
    dut._log.info("✓ Transceive REQA → ATQA OK")


@cocotb.test()
async def test_transceive_anticoll(dut):
    """Simulate ANTICOLL CL1 (0x93 0x20) and check UID + BCC response."""
    uid = (0xCA, 0xFE, 0xBA, 0xBE)
    mock = await setup(dut, uid=uid)

    # Flush + clear IRQs
    await nfc_write(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL, 0x80)
    await nfc_write(dut, Mfrc522SpiSlave.REG_COM_IRQ, 0x7F)

    # Write ANTICOLL CL1 into FIFO
    await nfc_write(dut, Mfrc522SpiSlave.REG_FIFO_DATA, 0x93)
    await nfc_write(dut, Mfrc522SpiSlave.REG_FIFO_DATA, 0x20)

    # Transceive + StartSend
    await nfc_write(dut, Mfrc522SpiSlave.REG_COMMAND, Mfrc522SpiSlave.CMD_TRANSCEIVE)
    await nfc_write(dut, Mfrc522SpiSlave.REG_BIT_FRAMING, 0x80)

    await Timer(500, unit="ns")

    # Check IRQs
    irq = await nfc_read(dut, Mfrc522SpiSlave.REG_COM_IRQ)
    assert irq & Mfrc522SpiSlave.COMIRQ_RX

    # Read response: 4 UID bytes + 1 BCC = 5 bytes
    level = await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 5, f"Expected FIFO level 5, got {level}"

    resp = []
    for _ in range(5):
        resp.append(await nfc_read(dut, Mfrc522SpiSlave.REG_FIFO_DATA))

    expected_bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
    assert resp[:4] == list(uid), f"UID mismatch: {resp[:4]}"
    assert resp[4] == expected_bcc, \
        f"BCC mismatch: expected {expected_bcc:#04x}, got {resp[4]:#04x}"
    dut._log.info(f"✓ ANTICOLL → UID={[hex(b) for b in resp[:4]]}, BCC={resp[4]:#04x} OK")


@cocotb.test()
async def test_busy_during_transaction(dut):
    """nfc_cmd_busy should be high while a transaction is in progress."""
    mock = await setup(dut)

    assert dut.nfc_cmd_busy.value == 0, "Should be idle before command"

    # Start a read but don't wait for done — check busy immediately
    dut.nfc_cmd_addr.value  = Mfrc522SpiSlave.REG_VERSION
    dut.nfc_cmd_write.value = 0
    dut.nfc_cmd_valid.value = 1
    await RisingEdge(dut.clk)
    dut.nfc_cmd_valid.value = 0
    await RisingEdge(dut.clk)

    assert dut.nfc_cmd_busy.value == 1, "Should be busy after command issued"

    # Now wait for completion
    await with_timeout(RisingEdge(dut.nfc_cmd_done), 500, "us")

    # After done, busy should drop on the next cycle
    await RisingEdge(dut.clk)
    assert dut.nfc_cmd_busy.value == 0, "Should be idle after done"
    dut._log.info("✓ Busy flag behaviour OK")


@cocotb.test()
async def test_back_to_back_writes(dut):
    """Issue writes immediately after each other — no extra wait."""
    mock = await setup(dut)

    # Write 5 values to a generic register
    for i in range(5):
        await nfc_write(dut, 0x14, i)

    # Final register value should be the last write
    result = await nfc_read(dut, 0x14)
    assert result == 4, f"Expected 4, got {result}"
    dut._log.info("✓ 5 back-to-back writes OK")


# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────

def test_mfrc522_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI
    spi_ext_dir = str(test_dir.parent / "cocotbext-spi")

    src = proj_dir / "src"
    pulp = src / "axi_spi_master"

    sources = [
        # PULP SPI master IP
        pulp / "spi_master_clkgen.sv",
        pulp / "spi_master_tx.sv",
        pulp / "spi_master_rx.sv",
        pulp / "spi_master_fifo.sv",
        pulp / "spi_master_controller.sv",
        pulp / "spi_master_axi_if.sv",
        pulp / "axi_spi_master.sv",
        # Our modules
        src / "axi_lite_master.sv",
        src / "nfc_spi.sv",
        src / "eeprom_spi.sv",
        src / "spi_init.sv",
        # Test wrapper
        test_dir / "spi_top_wrapper.sv",
    ]

    # Inject PYTHONPATH into the process environment so the cocotb
    # simulator subprocess can import test_mfrc522, mock_mrfc522,
    # and the cocotbext-spi submodule.
    extra_paths = [str(test_dir), spi_ext_dir]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        extra_paths.append(existing)
    os.environ["PYTHONPATH"] = os.pathsep.join(extra_paths)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_top_wrapper",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="spi_top_wrapper",
        test_module="test_mfrc522",
        waves=True,
    )


if __name__ == "__main__":
    test_mfrc522_runner()
