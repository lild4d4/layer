import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, with_timeout
import os
from cocotb_tools.runner import get_runner
from pathlib import Path


@cocotb.test()
async def test_simple_byte_write(dut):
    """
    Test a single byte write to the SPI Master.
    """

    # 1. Configuration and Clock Setup
    # The system clock (high speed)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # Note: If your RTL generates sclk internally from clk,
    # do NOT drive spi_clk from cocotb. If it's an input, keep this:
    # cocotb.start_soon(Clock(dut.sclk, 100, units="ns").start())

    # 2. Reset Phase (Active Low)
    dut._log.info("Applying Reset...")
    dut.reset.value = 1  # Using 'reset' from the blog's code (posedge reset)
    dut.start.value = 0
    dut.data_in.value = 0

    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 5)

    # 3. Drive Stimulus
    test_data = 0xA5
    dut._log.info(f"Starting SPI Write Transaction with data: {hex(test_data)}")

    dut.data_in.value = test_data
    dut.start.value = 1

    # Hold command for one clock cycle
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # 4. Wait for Transmission
    # Since the blog code doesn't have a 'busy' signal,
    # we monitor the Slave Select (ss) or count cycles.
    await with_timeout(RisingEdge(dut.ss), 10, "us")

    # 5. Verification
    assert dut.ss.value == 1, "Error: SS should be high after transaction"

    await ClockCycles(dut.clk, 20)
    dut._log.info("Test Complete")


# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────


def test_spi_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI
    spi_ext_dir = str(test_dir.parent / "cocotbext-spi")

    src = proj_dir / "src"

    sources = [
        # SPI master IP
        src
        / "spi_master.sv",
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
        hdl_toplevel="spi_master",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="spi_master",
        test_module="test_spi",
        waves=True,
    )


if __name__ == "__main__":
    test_spi_runner()
