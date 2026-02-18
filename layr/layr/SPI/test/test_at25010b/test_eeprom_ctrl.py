import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, First
import os
from pathlib import Path

from cocotbext.spi import SpiBus
from at25010b_mock import AT25010B_EEPROM
from cocotb_tools.runner import get_runner

CLK_PERIOD_NS = 10  # 100Mhz
RESET_CYCLES = 5
TRANSACTION_TIMEOUT_US = 500


def build_spi_bus(dut) -> SpiBus:
    """
    Build a SpiBus from the tb_top SPI port using custom signal names.

    The SpiBus.from_entity() method automatically finds signals by name,
    so we tell it the actual signal names used in eeprom_wire_modules.sv.
    """
    return SpiBus.from_entity(
        dut,
        sclk_name="spi_sclk",
        mosi_name="spi_mosi",
        miso_name="spi_miso",
        cs_name="cs_1",
    )


async def reset_dut(dut):
    """Assert reset for RESET_CYCLES, then release and wait for init."""
    dut.rst.value = 1
    dut.start.value = 0
    dut.get_key.value = 0

    for _ in range(RESET_CYCLES):
        await RisingEdge(dut.clk)

    dut.rst.value = 0

    await RisingEdge(dut.clk)


async def send_cmd(dut, *, write: bool, addr: int, wdata: int = 0) -> None:
    """
    Drive a one-cycle eeprom_start pulse to start a transaction.

    The caller must then wait for cmd_done (use wait_done()).
    """
    dut.eeprom_addr.value = addr & 0x7F
    dut.eeprom_start.value = 1
    await RisingEdge(dut.clk)
    dut.eeprom_start.value = 0


async def wait_done(dut, timeout_us: int = TRANSACTION_TIMEOUT_US) -> None:
    """
    Block until done pulses high, or raise TestFailure on timeout.
    """
    timeout_trigger = Timer(timeout_us, "us")
    done_trigger = RisingEdge(dut.done)

    result = await First(done_trigger, timeout_trigger)
    if result is timeout_trigger:
        raise Exception(f"Timed out after {timeout_us} µs waiting for done. ")

    # eeprom_done is a single-cycle pulse; make sure we sampled it on a rising edge
    await RisingEdge(dut.clk)


# ──────────────────────────────────────────────────────────────────────────────
# Common fixture: start clock + reset + attach EEPROM mock
# ──────────────────────────────────────────────────────────────────────────────

KEY_A = bytes.fromhex("39558d1f193656ab8b4b65e25ac48474")
ID_A = bytes.fromhex("bbe8278a67f960605adafd6f63cf7ba7")


async def setup(dut) -> AT25010B_EEPROM:
    """
    Start the simulation clock, reset the DUT, and attach the EEPROM mock.
    Returns the mock so tests can pre-load / inspect memory.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    eeprom = AT25010B_EEPROM(build_spi_bus(dut))

    eeprom.load_memory(KEY_A, offset=0x00)
    eeprom.load_memory(ID_A, offset=0x40)

    await reset_dut(dut)
    return eeprom


#
# Tests
#


@cocotb.test()
async def test_reset_state(dut):
    """After reset, eeprom_busy must be low and eeprom_done must be low."""
    await setup(dut)
    await RisingEdge(dut.clk)

    assert int(dut.busy.value) == 0, "busy should be 0 after reset"
    assert int(dut.done.value) == 0, "done should be 0 after reset"


@cocotb.test()
async def test_get_key(dut):
    """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
    _ = await setup(dut)

    dut.get_key.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    await wait_done(dut)

    result = dut.buffer.value
    expected = int.from_bytes(KEY_A, byteorder="big")
    assert result == expected, f"Expected {expected:#x}, got {result:#x}"


@cocotb.test()
async def test_get_id(dut):
    """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
    _ = await setup(dut)

    dut.get_key.value = 0
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    await wait_done(dut)

    result = dut.buffer.value
    expected = int.from_bytes(ID_A, byteorder="big")
    assert result == expected, f"Expected {expected:#x}, got {result:#x}"


#
# Runner
#


def test_eeprom_ctrl_e2e_runner():
    """
    End-to-end test runner for eeprom_spi + axi_lite_master + axi_spi_master.

    This builds the full RTL hierarchy (all three modules + tb_top wrapper)
    and runs all tests in test_eeprom.py.
    """
    sim = os.getenv("SIM", "icarus")
    spi_module_path = Path(__file__).resolve().parent.parent.parent
    src_dir = spi_module_path / "src"
    this_dir = Path(__file__).resolve().parent

    sources = [
        src_dir / "eeprom_spi.sv",
        src_dir / "eeprom_ctrl.sv",
        src_dir / "spi_master.sv",
        src_dir / "spi_ctrl.sv",
        src_dir / "clock_divider.sv",
        this_dir / "test_eeprom_ctrl_tb.sv",
    ]

    sources = [s for s in sources if s.exists()]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_eeprom_ctrl_tb",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_eeprom_ctrl_tb",
        test_module="test_eeprom_ctrl",
        waves=True,
    )


if __name__ == "__main__":
    test_eeprom_ctrl_e2e_runner()
