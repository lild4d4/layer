import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
import os
from cocotb_tools.runner import get_runner
from pathlib import Path


async def reset(dut):
    """Apply reset pulse."""
    await FallingEdge(dut.clk)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_eeprom_fpga_compiles(dut):
    """Smoke test: clock starts, reset completes, design is alive."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Just run a handful of cycles to confirm nothing blows up
    for _ in range(100):
        await RisingEdge(dut.clk)


# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────


def test_eeprom_fpga_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI

    src = proj_dir / "src"
    sources = [*src.glob("*.sv")]
    sources.append(test_dir / "test_fpga_mfrc_poll_top.sv")
    
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_fpga_mfrc_poll_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_fpga_mfrc_poll_top",
        test_module="test_fpga_mfrc_poll_top",
        waves=True,
    )