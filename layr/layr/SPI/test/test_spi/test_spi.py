import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, with_timeout
import os
from cocotb_tools.runner import get_runner
from pathlib import Path


async def spi_slave_manual(dut, reply_byte):
    """
    A manual SPI slave that works directly with the spi_master module
    (which has no SS pin).  It watches sclk edges to track the transfer.

    The master is CPOL=0: sclk idles low, data is set on rising edge,
    sampled on falling edge.
    """
    # Wait for the first rising edge of sclk (transfer starts)
    await RisingEdge(dut.sclk)

    rx_byte = 0
    for i in range(8):
        if i > 0:
            await RisingEdge(dut.sclk)
        # Sample MOSI on rising edge
        bit = int(dut.mosi.value)
        rx_byte = (rx_byte << 1) | bit

        # Drive MISO — master samples on falling edge (state 2)
        dut.miso.value = (reply_byte >> (7 - i)) & 1

        await FallingEdge(dut.sclk)

    # Let miso settle for a couple clocks then clear
    await ClockCycles(dut.clk, 2)
    dut.miso.value = 0

    return rx_byte


@cocotb.test()
async def test_simple_byte_write(dut):
    """
    Test a single byte write to the SPI Master.
    """

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut._log.info("Applying Reset...")
    dut.reset.value = 1
    dut.start.value = 0
    dut.data_in.value = 0
    dut.miso.value = 0

    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 5)

    test_data = 0xA5
    dut._log.info(f"Starting SPI Write Transaction with data: {hex(test_data)}")

    dut.data_in.value = test_data
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Wait for done pulse
    await with_timeout(RisingEdge(dut.done), 10, "us")
    # done and busy update on the same cycle; wait one more for busy to settle
    await RisingEdge(dut.clk)

    assert dut.busy.value == 0, "Error: busy should be low after transaction"

    await ClockCycles(dut.clk, 20)
    dut._log.info("Test Complete")


@cocotb.test()
async def test_spi_slave_receives_byte(dut):
    """
    Verify that the master correctly transmits data on MOSI and
    receives the slave reply on MISO (full-duplex, 8 clocks).
    Uses a manual SPI slave (spi_master has no SS pin).
    """

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut._log.info("Applying reset ...")
    dut.reset.value = 1
    dut.start.value = 0
    dut.data_in.value = 0
    dut.miso.value = 0
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 5)

    test_data = 0xA5
    slave_reply = 0x3C
    dut._log.info(f"Starting SPI transaction — TX: {hex(test_data)}, "
                  f"expected slave reply: {hex(slave_reply)}")

    # Start the manual slave in the background
    slave_task = cocotb.start_soon(spi_slave_manual(dut, slave_reply))

    dut.data_in.value = test_data
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Wait for done
    await with_timeout(RisingEdge(dut.done), 50, "us")
    dut._log.info("SPI transaction complete")

    # Check what the slave captured on MOSI
    received_by_slave = await with_timeout(slave_task.join(), 10, "us")
    dut._log.info(f"Slave received on MOSI : {hex(received_by_slave)}")

    assert received_by_slave == test_data, (
        f"Slave saw {hex(received_by_slave)} on MOSI, expected {hex(test_data)}"
    )

    # Check what the master captured on MISO (data_out register)
    await ClockCycles(dut.clk, 2)
    master_rx = int(dut.data_out.value)
    dut._log.info(f"Master data_out (MISO) : {hex(master_rx)}")

    assert master_rx == slave_reply, (
        f"Master data_out is {hex(master_rx)}, expected {hex(slave_reply)}"
    )

    await ClockCycles(dut.clk, 10)
    dut._log.info("test_spi_slave_receives_byte PASSED ✓")


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
        src / "spi_master.sv",
    ]

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
