"""
test_mfrc_reg_if.py
Tests for mfrc_reg_if → spi_ctrl → spi_master chain, with the
Mfrc522SpiSlave mock attached to the SPI bus via cocotbext-spi.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, with_timeout, Timer
import os
from cocotb_tools.runner import get_runner
from pathlib import Path

from cocotbext.spi import SpiConfig, SpiBus
from mock_mfrc522 import Mfrc522SpiSlave


# SPI config matching our spi_master RTL (CPOL=0, slave sees CPHA=1)
_spi_ctrl_config = SpiConfig(
    word_width=8,
    cpol=False,
    cpha=True,
    msb_first=True,
    cs_active_low=True,
    frame_spacing_ns=1,
    data_output_idle=1,
)


def _int_to_bytes(val: int, count: int) -> list[int]:
    """Extract count bytes from a 256-bit integer (byte 0 = MSB)."""
    result = []
    for i in range(count):
        shift = 255 - i * 8
        result.append((val >> (shift - 7)) & 0xFF)
    return result


def _bytes_to_int(byte_list: list[int]) -> int:
    """Pack a list of bytes into a 256-bit integer (byte 0 = MSB)."""
    val = 0
    for b in byte_list:
        val = (val << 8) | b
    val <<= (32 - len(byte_list)) * 8
    return val


# ─────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────

async def _reset(dut):
    """Apply reset and initialise all inputs."""
    dut.rst_n.value = 0
    dut.req_valid.value = 0
    dut.req_write.value = 0
    dut.req_addr.value = 0
    dut.req_len.value = 0
    dut.req_wdata.value = 0
    dut.miso.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


def _attach_mock(dut, version=0x92):
    """Attach the MFRC522 mock to cs0 with our spi_master-compatible config."""
    spi_bus = SpiBus.from_entity(dut, cs_name="cs0")
    return Mfrc522SpiSlave(spi_bus, version=version, config=_spi_ctrl_config)


async def _write_reg(dut, addr: int, data: int, burst_len: int = 1):
    """Issue a register write via mfrc_reg_if and wait for resp_valid."""
    dut.req_addr.value = addr & 0x3F
    dut.req_write.value = 1
    dut.req_len.value = burst_len
    dut.req_wdata.value = _bytes_to_int([data & 0xFF] * burst_len)
    dut.req_valid.value = 1
    await RisingEdge(dut.clk)
    dut.req_valid.value = 0

    for _ in range(50000):
        await RisingEdge(dut.clk)
        if dut.resp_valid.value == 1:
            return
    assert False, "Timed out waiting for resp_valid (write)"


async def _read_reg(dut, addr: int, burst_len: int = 1) -> int | list[int]:
    """Issue a register read via mfrc_reg_if and return the data."""
    dut.req_addr.value = addr & 0x3F
    dut.req_write.value = 0
    dut.req_len.value = burst_len
    dut.req_wdata.value = 0
    dut.req_valid.value = 1
    await RisingEdge(dut.clk)
    dut.req_valid.value = 0

    for _ in range(50000):
        await RisingEdge(dut.clk)
        if dut.resp_valid.value == 1:
            break
    else:
        assert False, "Timed out waiting for resp_valid (read)"

    rx_val = int(dut.resp_rdata.value)
    if burst_len == 1:
        return _int_to_bytes(rx_val, 1)[0]
    return _int_to_bytes(rx_val, burst_len)


# ─────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_read_version_register(dut):
    """Read MFRC522 VersionReg (0x37) — should return 0x92."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut, version=0x92)

    result = await _read_reg(dut, Mfrc522SpiSlave.REG_VERSION)
    dut._log.info(f"VersionReg = {result:#04x}")
    assert result == 0x92, f"Expected 0x92, got {result:#04x}"
    dut._log.info("test_read_version_register PASSED ✓")


@cocotb.test()
async def test_read_version_alternate(dut):
    """Instantiate mock with version 0x91 and verify."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut, version=0x91)

    result = await _read_reg(dut, Mfrc522SpiSlave.REG_VERSION)
    assert result == 0x91, f"Expected 0x91, got {result:#04x}"
    dut._log.info("test_read_version_alternate PASSED ✓")


@cocotb.test()
async def test_write_and_readback(dut):
    """Write a generic register, then read it back — full round-trip."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    test_addr = 0x14
    test_val = 0xA5

    await _write_reg(dut, test_addr, test_val)
    assert mock._regs[test_addr] == test_val, "Mock register not updated"

    result = await _read_reg(dut, test_addr)
    dut._log.info(f"Write {test_val:#04x} → read back {result:#04x}")
    assert result == test_val, f"Expected {test_val:#04x}, got {result:#04x}"
    dut._log.info("test_write_and_readback PASSED ✓")


@cocotb.test()
async def test_command_reg_reset_default(dut):
    """CommandReg resets to 0x20 (RcvOff=1)."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    result = await _read_reg(dut, Mfrc522SpiSlave.REG_COMMAND)
    assert result == 0x20, f"Expected 0x20, got {result:#04x}"
    dut._log.info("test_command_reg_reset_default PASSED ✓")


@cocotb.test()
async def test_fifo_write_and_read(dut):
    """Write bytes into FIFODataReg, check level, read them back."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    # Write 3 bytes into FIFO
    for b in [0x11, 0x22, 0x33]:
        await _write_reg(dut, Mfrc522SpiSlave.REG_FIFO_DATA, b)

    # Check FIFO level
    level = await _read_reg(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 3, f"Expected FIFO level 3, got {level}"

    # Read back in FIFO order
    for expected in [0x11, 0x22, 0x33]:
        got = await _read_reg(dut, Mfrc522SpiSlave.REG_FIFO_DATA)
        assert got == expected, f"FIFO: expected {expected:#04x}, got {got:#04x}"

    # FIFO should be empty
    level = await _read_reg(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 0, f"Expected FIFO level 0, got {level}"
    dut._log.info("test_fifo_write_and_read PASSED ✓")


@cocotb.test()
async def test_fifo_flush(dut):
    """Writing FlushBuffer bit (0x80) to FIFOLevelReg clears the FIFO."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    for b in [0xAA, 0xBB, 0xCC]:
        await _write_reg(dut, Mfrc522SpiSlave.REG_FIFO_DATA, b)

    level = await _read_reg(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 3

    # Flush
    await _write_reg(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL, 0x80)

    level = await _read_reg(dut, Mfrc522SpiSlave.REG_FIFO_LEVEL)
    assert level == 0, f"Expected 0 after flush, got {level}"
    dut._log.info("test_fifo_flush PASSED ✓")


@cocotb.test()
async def test_soft_reset(dut):
    """Writing CMD_SOFTRESET resets registers to defaults."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    # Write a known value
    await _write_reg(dut, 0x14, 0x55)
    assert mock._regs[0x14] == 0x55

    # Soft reset
    await _write_reg(dut, Mfrc522SpiSlave.REG_COMMAND, Mfrc522SpiSlave.CMD_SOFTRESET)
    await Timer(200, unit="ns")

    # Should be back to default
    result = await _read_reg(dut, 0x14)
    assert result == 0x00, f"Expected 0x00 after reset, got {result:#04x}"

    # Version still there
    result = await _read_reg(dut, Mfrc522SpiSlave.REG_VERSION)
    assert result == 0x92, f"Expected 0x92, got {result:#04x}"
    dut._log.info("test_soft_reset PASSED ✓")


@cocotb.test()
async def test_req_ready_and_resp_ok(dut):
    """req_ready should be high when idle, resp_ok should be 1 on completion."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    # Should be ready before any request
    assert dut.req_ready.value == 1, "req_ready should be high when idle"

    # Start a read but don't wait — check ready drops
    dut.req_addr.value = Mfrc522SpiSlave.REG_VERSION
    dut.req_write.value = 0
    dut.req_len.value = 1
    dut.req_valid.value = 1
    await RisingEdge(dut.clk)
    dut.req_valid.value = 0
    await RisingEdge(dut.clk)

    assert dut.req_ready.value == 0, "req_ready should be low during transaction"

    # Wait for completion
    for _ in range(50000):
        await RisingEdge(dut.clk)
        if dut.resp_valid.value == 1:
            break

    assert dut.resp_ok.value == 1, "resp_ok should be 1"

    await RisingEdge(dut.clk)
    assert dut.req_ready.value == 1, "req_ready should be high after completion"
    dut._log.info("test_req_ready_and_resp_ok PASSED ✓")


@cocotb.test()
async def test_back_to_back_writes(dut):
    """Issue writes immediately after each other."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    for i in range(5):
        await _write_reg(dut, 0x14, i)

    result = await _read_reg(dut, 0x14)
    assert result == 4, f"Expected 4, got {result}"
    dut._log.info("test_back_to_back_writes PASSED ✓")


@cocotb.test()
async def test_cs0_used_cs1_idle(dut):
    """Verify that mfrc_reg_if always uses cs0 and cs1 stays high."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    await _read_reg(dut, Mfrc522SpiSlave.REG_VERSION)

    # After transaction, both CS lines should be deasserted
    assert dut.cs0.value == 1, "cs0 should be deasserted after transfer"
    assert dut.cs1.value == 1, "cs1 should always be high (never used)"
    dut._log.info("test_cs0_used_cs1_idle PASSED ✓")


# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────

def test_mfrc_reg_if_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI
    spi_ext_dir = str(test_dir.parent / "cocotbext-spi")

    src = proj_dir / "src"

    sources = [
        src / "spi_master.sv",
        src / "spi_ctrl.sv",
        src / "mfrc_reg_if.sv",
        test_dir / "test_mfrc_reg_if_top.sv",
    ]

    extra_paths = [str(test_dir), spi_ext_dir]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        extra_paths.append(existing)
    os.environ["PYTHONPATH"] = os.pathsep.join(extra_paths)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_mfrc_reg_if_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_mfrc_reg_if_top",
        test_module="test_mfrc_reg_if",
        waves=True,
    )


if __name__ == "__main__":
    test_mfrc_reg_if_runner()
