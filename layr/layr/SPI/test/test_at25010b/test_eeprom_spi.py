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
    dut.eeprom_start.value = 0
    dut.eeprom_write.value = 0
    dut.eeprom_addr.value = 0
    dut.eeprom_wdata.value = 0

    for _ in range(RESET_CYCLES):
        await RisingEdge(dut.clk)

    dut.rst.value = 0

    await RisingEdge(dut.clk)


async def send_cmd(dut, *, write: bool, addr: int, wdata: int = 0) -> None:
    """
    Drive a one-cycle eeprom_start pulse to start a transaction.

    The caller must then wait for cmd_done (use wait_done()).
    """
    dut.eeprom_write.value = int(write)
    dut.eeprom_addr.value = addr & 0x7F
    dut.eeprom_wdata.value = wdata & 0xFF
    dut.eeprom_start.value = 1
    await RisingEdge(dut.clk)
    dut.eeprom_start.value = 0


async def wait_done(dut, timeout_us: int = TRANSACTION_TIMEOUT_US) -> None:
    """
    Block until eeprom_done pulses high, or raise TestFailure on timeout.
    """
    timeout_trigger = Timer(timeout_us, "us")
    done_trigger = RisingEdge(dut.eeprom_done)

    result = await First(done_trigger, timeout_trigger)
    if result is timeout_trigger:
        # Gather debug info
        try:
            fsm_state = int(dut.u_eeprom_spi.state.value)
            axi_busy = int(dut.u_eeprom_spi.axi_busy.value)
        except Exception:
            fsm_state = "?"
            axi_busy = "?"
        raise Exception(
            f"Timed out after {timeout_us} µs waiting for eeprom_done. "
            f"FSM state={fsm_state}, eeprom_busy={int(dut.eeprom_busy.value)}, "
            f"axi_busy={axi_busy}"
        )
    # eeprom_done is a single-cycle pulse; make sure we sampled it on a rising edge
    await RisingEdge(dut.clk)


async def eeprom_write(dut, addr: int, data: int) -> None:
    """Issue a write command and wait for completion."""
    await send_cmd(dut, write=True, addr=addr, wdata=data)
    await wait_done(dut)


async def eeprom_read(dut, addr: int) -> int:
    """Issue a read command, wait for completion, return eeprom_rdata."""
    await send_cmd(dut, write=False, addr=addr)
    await wait_done(dut)
    return int(dut.eeprom_rdata.value)


# ──────────────────────────────────────────────────────────────────────────────
# Common fixture: start clock + reset + attach EEPROM mock
# ──────────────────────────────────────────────────────────────────────────────


async def setup(dut) -> AT25010B_EEPROM:
    """
    Start the simulation clock, reset the DUT, and attach the EEPROM mock.
    Returns the mock so tests can pre-load / inspect memory.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    eeprom = AT25010B_EEPROM(build_spi_bus(dut))
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

    assert int(dut.eeprom_busy.value) == 0, "eeprom_busy should be 0 after reset"
    assert int(dut.eeprom_done.value) == 0, "eeprom_busy should be 0 after reset"


@cocotb.test()
async def test_read_single_byte(dut):
    """Read one byte from EEPROM address 0x00."""
    eeprom = await setup(dut)

    # Pre-load a known value into the EEPROM mock at address 0x00
    eeprom.memory[0x00] = 0xAB

    # Read back the byte
    result = await eeprom_read(dut, addr=0x00)

    assert result == 0xAB, f"Expected 0xAB, got {result}"


#
# Runner
#


def test_eeprom_spi_e2e_runner():
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
        src_dir / "spi_master.sv",
        this_dir / "test_eeprom_tb.sv",
    ]

    sources = [s for s in sources if s.exists()]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_eeprom_tb",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_eeprom_tb",
        test_module="test_eeprom_spi",
        waves=True,
    )


if __name__ == "__main__":
    test_eeprom_spi_e2e_runner()
