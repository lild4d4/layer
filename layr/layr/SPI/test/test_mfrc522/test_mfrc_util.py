"""
test_mfrc_util.py
Tests for mfrc_util → spi_ctrl → spi_master chain, with the
Mfrc522SpiSlave mock attached to the SPI bus via cocotbext-spi.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import os
from cocotb_tools.runner import get_runner
from pathlib import Path

from cocotbext.spi import SpiBus
from mock_mfrc522 import Mfrc522SpiSlave

# ─────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────


async def _reset(dut):
    """Apply reset and initialise all inputs."""
    dut.rst.value = 1
    dut.start.value = 0
    dut.miso.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 5)


def _attach_mock(dut, version=0x92):
    """Attach the MFRC522 mock to cs0."""
    spi_bus = SpiBus.from_entity(dut, cs_name="cs0")
    mock = Mfrc522SpiSlave(spi_bus)
    mock._version = version
    mock._regs[Mfrc522SpiSlave.REG_VERSION] = version
    return mock


async def _run_util(dut, timeout=50000):
    """Pulse start and wait for done."""
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            return
    assert False, "Timed out waiting for done"


# ─────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────


@cocotb.test()
async def test_version_0x92(dut):
    """mfrc_util should read VersionReg and return 0x92."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    _attach_mock(dut, version=0x92)

    await _run_util(dut)

    assert dut.ok.value == 1, "ok should be 1"
    assert (
        int(dut.version.value) == 0x92
    ), f"Expected 0x92, got {int(dut.version.value):#04x}"
    dut._log.info("test_version_0x92 PASSED ✓")


@cocotb.test()
async def test_version_0x91(dut):
    """mfrc_util should read VersionReg and return 0x91."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    _attach_mock(dut, version=0x91)

    await _run_util(dut)

    assert dut.ok.value == 1, "ok should be 1"
    assert (
        int(dut.version.value) == 0x91
    ), f"Expected 0x91, got {int(dut.version.value):#04x}"
    dut._log.info("test_version_0x91 PASSED ✓")


@cocotb.test()
async def test_ready_signal(dut):
    """ready should be high when idle and drop during transaction."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    _attach_mock(dut)

    assert dut.ready.value == 1, "ready should be high when idle"

    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await RisingEdge(dut.clk)

    assert dut.ready.value == 0, "ready should be low during transaction"

    for _ in range(50000):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            break

    await RisingEdge(dut.clk)
    assert dut.ready.value == 1, "ready should be high after completion"
    dut._log.info("test_ready_signal PASSED ✓")


@cocotb.test()
async def test_back_to_back(dut):
    """Issue two reads back-to-back — both should succeed."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    _attach_mock(dut, version=0x92)

    await _run_util(dut)
    assert int(dut.version.value) == 0x92

    await _run_util(dut)
    assert int(dut.version.value) == 0x92
    assert dut.ok.value == 1
    dut._log.info("test_back_to_back PASSED ✓")


# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────


def test_mfrc_util_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI
    spi_ext_dir = str(test_dir.parent / "cocotbext-spi")

    src = proj_dir / "src"

    sources = [
        src / "spi_master.sv",
        src / "spi_ctrl.sv",
        src / "mfrc_util.sv",
        src / "mfrc_reg_if.sv",
        test_dir / "test_mfrc_util_top.sv",
    ]

    extra_paths = [str(test_dir), spi_ext_dir]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        extra_paths.append(existing)
    os.environ["PYTHONPATH"] = os.pathsep.join(extra_paths)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_mfrc_util_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_mfrc_util_top",
        test_module="test_mfrc_util",
        waves=True,
    )


if __name__ == "__main__":
    test_mfrc_util_runner()
