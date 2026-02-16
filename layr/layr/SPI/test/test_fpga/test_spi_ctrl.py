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
async def test_spi_ctrl_top(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.miso.value = 1
    for i in range(2000):
        await RisingEdge(dut.clk)

# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────


def test_spi_ctrl_top_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI

    src = proj_dir / "src"

    sources = [
        src / "spi_master.sv",
        src / "spi_ctrl.sv",
        src / "clock_divider.sv",
        test_dir / "fpga" / "test_spi_ctrl_top.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_spi_ctrl_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_spi_ctrl_top",
        test_module="test_spi_ctrl",
        waves=True,
    )


if __name__ == "__main__":
    test_spi_ctrl_top_runner()
