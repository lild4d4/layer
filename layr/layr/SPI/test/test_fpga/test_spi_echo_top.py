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
async def test_spi_echo_top(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.miso.value = 1
    for i in range(2000):
        await RisingEdge(dut.clk)

# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────


def test_spi_echo_top_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI
    spi_ext_dir = str(test_dir.parent / "cocotbext-spi")

    src = proj_dir / "src"

    sources = [
        src / "spi_master.sv",
        src / "clock_divider.sv",
        test_dir / "test_spi" / "spi_echo.sv",
        test_dir / "test_fpga" / "spi_echo_top.sv",
    ]

    extra_paths = [str(test_dir), spi_ext_dir]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        extra_paths.append(existing)
    os.environ["PYTHONPATH"] = os.pathsep.join(extra_paths)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_echo_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="spi_echo_top",
        test_module="test_spi_echo_top",
        waves=True,
    )


if __name__ == "__main__":
    test_spi_echo_top_runner()
