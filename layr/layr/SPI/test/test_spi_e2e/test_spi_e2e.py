import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, First
import os
from pathlib import Path

from cocotbext.spi import SpiBus
from layr.layr.SPI.test.test_at25010b.at25010b_mock import AT25010B_EEPROM
from layr.layr.SPI.test.test_mfrc522.mock_mfrc522 import Mfrc522SpiSlave
from cocotb_tools.runner import get_runner

CLK_PERIOD_NS = 10  # 100Mhz
RESET_CYCLES = 5
TRANSACTION_TIMEOUT_US = 500


def build_spi_bus(dut, cs: int) -> SpiBus:
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
        cs_name=f"cs_{cs}",
    )


async def reset_dut(dut):
    """Assert reset for RESET_CYCLES, then release and wait for init."""
    dut.rst.value = 1

    # TODO: add other sensible default resets

    for _ in range(RESET_CYCLES):
        await RisingEdge(dut.clk)

    dut.rst.value = 0

    await RisingEdge(dut.clk)


async def wait_done(dut, wait_cond, timeout_us: int = TRANSACTION_TIMEOUT_US) -> None:
    """
    Block until wait_done pulses high, or raise TestFailure on timeout.
    """
    timeout_trigger = Timer(timeout_us, "us")
    done_trigger = RisingEdge(wait_cond)

    result = await First(done_trigger, timeout_trigger)
    if result is timeout_trigger:
        raise Exception(f"Timed out after {timeout_us} µs waiting for done. ")

    await RisingEdge(dut.clk)


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    eeprom = await eeprom_setup(dut)
    mfrc = await mfrc_setup(dut)

    return (eeprom, mfrc)


#
# EEPROM Stuff
#

KEY_A = bytes.fromhex("39558d1f193656ab8b4b65e25ac48474")
ID_A = bytes.fromhex("bbe8278a67f960605adafd6f63cf7ba7")


async def eeprom_setup(dut) -> AT25010B_EEPROM:
    """
    Start the simulation clock, reset the DUT, and attach the EEPROM mock.
    Returns the mock so tests can pre-load / inspect memory.
    """
    eeprom = AT25010B_EEPROM(build_spi_bus(dut, 1))

    eeprom.load_memory(KEY_A, offset=0x00)
    eeprom.load_memory(ID_A, offset=0x40)

    await reset_dut(dut)
    return eeprom


async def eeprom_send_cmd(dut, get_key: int) -> None:
    """
    Drive a one-cycle eeprom_start pulse to start a transaction.

    The caller must then wait for cmd_done (use wait_done()).
    """
    dut.eeprom_get_key.value = get_key
    dut.eeprom_start.value = 1
    await RisingEdge(dut.clk)
    dut.eeprom_start.value = 0

    await wait_done(dut, dut.eeprom_done)

    return dut.eeprom_rbuffer.value


#
# MFRC Stuff
#


async def mfrc_setup(dut):
    return None


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
async def test_eeprom_get_key(dut):
    """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
    _ = await setup(dut)

    result = await eeprom_send_cmd(dut, 1)
    expected = int.from_bytes(KEY_A, byteorder="big")
    assert result == expected, f"Expected {expected:#x}, got {result:#x}"


@cocotb.test()
async def test_eeprom_get_id(dut):
    """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
    _ = await setup(dut)

    result = await eeprom_send_cmd(dut, 0)
    expected = int.from_bytes(ID_A, byteorder="big")
    assert result == expected, f"Expected {expected:#x}, got {result:#x}"


#
# Runner
#


def test_spi_e2e_runner():
    sim = os.getenv("SIM", "icarus")
    spi_module_path = Path(__file__).resolve().parent.parent.parent
    src_dir = spi_module_path / "src"
    sources = list(src_dir.glob("*.sv"))

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="spi_top",
        test_module="test_spi_e2e",
        waves=True,
    )


if __name__ == "__main__":
    test_spi_e2e_runner()
