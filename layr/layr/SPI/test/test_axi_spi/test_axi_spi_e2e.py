"""
test_eeprom.py  –  End-to-end cocotb tests for the eeprom_spi FSM.

DUT chain
---------
cocotb drives:
    dut.cmd_valid / cmd_write / cmd_addr / cmd_wdata

Through RTL:
    eeprom_spi  →  axi_lite_master  →  axi_spi_master  →  SPI pins

AT25010B_EEPROM mock receives SPI and responds on:
    spi_clk / spi_csn0 / spi_sdo0 (MOSI) / spi_sdi0 (MISO)

Signal naming in tb_top
-----------------------
    dut.clk, dut.rst_n
    dut.cmd_valid, dut.cmd_write, dut.cmd_addr, dut.cmd_wdata
    dut.cmd_rdata, dut.cmd_done, dut.cmd_busy
    dut.spi_clk, dut.spi_csn0, dut.spi_sdo0, dut.spi_sdi0

SpiBus construction
-------------------
axi_spi_master drives MOSI on spi_sdo0 and reads MISO on spi_sdi0.
From the EEPROM mock's perspective:
    sclk  = dut.spi_clk
    cs    = dut.spi_csn0   (active-low)
    mosi  = dut.spi_sdo0   (master→slave)
    miso  = dut.spi_sdi0   (slave→master)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, First
import os
from pathlib import Path
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "cocotbext-spi"))
from cocotbext.spi import SpiMaster, SpiBus, SpiConfig, SpiSlaveBase
from cocotb_tools.runner import get_runner

# Simple SPI Slave


class SimpleSpiSlave(SpiSlaveBase):
    def __init__(self, bus):
        self._config = SpiConfig()
        self.content = 0
        super().__init__(bus)

    async def get_content(self):
        await self.idle.wait()
        return self.content

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()

        self.content = int(await self._shift(16, tx_word=(0xAAAA)))

        await frame_end


# ──────────────────────────────────────────────────────────────────────────────
# Constants matching eeprom_spi / axi_spi_master configuration
# ──────────────────────────────────────────────────────────────────────────────
CLK_PERIOD_NS = 10  # 100 MHz
RESET_CYCLES = 5
# Worst-case cycles to complete one full EEPROM transaction:
#   ~16 FSM states × a few AXI cycles each + SPI clocking
TRANSACTION_TIMEOUT_US = 500

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────


def build_spi_bus(dut) -> SpiBus:
    """
    Build a SpiBus from the tb_top SPI port using custom signal names.

    The SpiBus.from_entity() method automatically finds signals by name,
    so we tell it the actual signal names used in eeprom_wire_modules.sv.
    """
    return SpiBus.from_entity(
        dut,
        sclk_name="spi_clk",
        mosi_name="spi_sdo0",
        miso_name="spi_sdi0",
        cs_name="spi_csn0",
    )


async def reset_dut(dut):
    """Assert reset for RESET_CYCLES, then release and wait for init."""
    dut.rst_n.value = 1

    # TODO: set sensible defaults
    dut.req_addr_i.value = 0x0
    dut.req_wdata_i.value = 0x0
    dut.req_write_i.value = 0x0
    dut.req_valid_i.value = 0x0

    for _ in range(RESET_CYCLES):
        await RisingEdge(dut.clk)

    dut.rst_n.value = 0

    # Wait for the one-time SPI clock-divider init to complete.
    # The eeprom_spi FSM starts in S_INIT_CLKDIV and transitions to S_IDLE
    # after the AXI write finishes (~8-10 cycles).  cmd_busy is NOT asserted
    # during init states, but we need to let the AXI transaction finish so
    # the SPI clock divider is properly configured before any user commands.
    for _ in range(50):
        await RisingEdge(dut.clk)


async def send_byte(dut):
    dut.req_addr_i.value = 0xDE
    dut.req_wdata_i.value = 0xAD
    dut.req_write_i.value = 1
    dut.req_valid_i.value = 1
    await RisingEdge(dut.clk)
    dut.req_valid_i.value = 0


async def wait_done(dut, timeout_us: int = TRANSACTION_TIMEOUT_US) -> None:
    """
    Block until cmd_done pulses high, or raise TestFailure on timeout.
    """
    timeout_trigger = Timer(timeout_us, "us")
    done_trigger = RisingEdge(dut.busy_o)

    result = await First(done_trigger, timeout_trigger)
    if result is timeout_trigger:
        # Gather debug info
        try:
            axi_busy = int(dut.busy_o)
        except Exception:
            axi_busy = "?"
        raise Exception(
            f"Timed out after {timeout_us} µs waiting for cmd_done. "
            f"axi_busy={axi_busy}"
        )
    # cmd_done is a single-cycle pulse; make sure we sampled it on a rising edge
    await RisingEdge(dut.clk)


# ──────────────────────────────────────────────────────────────────────────────
# Common fixture: start clock + reset + attach EEPROM mock
# ──────────────────────────────────────────────────────────────────────────────


async def setup(dut):
    """,
    Start the simulation clock, reset the DUT, and attach the EEPROM mock.
    Returns the mock so tests can pre-load / inspect memory.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    slave = SimpleSpiSlave(build_spi_bus(dut))
    await reset_dut(dut)
    return slave


# ══════════════════════════════════════════════════════════════════════════════
# Tests
# ══════════════════════════════════════════════════════════════════════════════


# ── 1. Sanity: DUT comes out of reset in IDLE ─────────────────────────────────
@cocotb.test()
async def test_send_byte(dut):
    """After reset, cmd_busy must be low and cmd_done must be low."""
    slave = await setup(dut)
    await RisingEdge(dut.clk)

    await send_byte(dut)
    await wait_done(dut)
    content = await slave.get_content()

    assert content


# -- Runner --


def test_axi_spi_e2e_runner():
    """
    End-to-end test runner for eeprom_spi + axi_lite_master + axi_spi_master.

    This builds the full RTL hierarchy (all three modules + tb_top wrapper)
    and runs all tests in test_eeprom.py.
    """
    sim = os.getenv("SIM", "icarus")
    spi_module_path = Path(__file__).resolve().parent.parent.parent

    src_dir = spi_module_path / "src"

    axi_spi_ip_dir = src_dir / "axi_spi_master"

    # All RTL sources
    # IMPORTANT: axi_spi_master depends on several sub-modules from the PULP repo.
    # List them explicitly OR use a glob if they're all in rtl/
    sources = [
        # Your modules
        src_dir / "axi_lite_master.sv",
        # PULP axi_spi_master + all dependencies
        # (adjust filenames to match what you actually have)
        axi_spi_ip_dir / "axi_spi_master.sv",
        axi_spi_ip_dir / "spi_master_axi_if.sv",
        axi_spi_ip_dir / "spi_master_controller.sv",
        axi_spi_ip_dir / "spi_master_fifo.sv",
        axi_spi_ip_dir / "spi_master_clkgen.sv",
        axi_spi_ip_dir / "spi_master_rx.sv",
        axi_spi_ip_dir / "spi_master_tx.sv",
        # Testbench top-level wrapper
        spi_module_path / "test" / "test_axi_spi" / "axi_spi_test_wiring.sv",
    ]

    # Filter out any files that don't exist (in case PULP naming differs)
    sources = [s for s in sources if s.exists()]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="axi_spi_test_wiring",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="axi_spi_test_wiring",
        test_module="test_axi_spi_e2e",
        waves=True,
    )


if __name__ == "__main__":
    test_axi_spi_e2e_runner()
