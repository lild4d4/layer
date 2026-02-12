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
from cocotbext.spi import SpiBus
from AT25010B_EEPROM_mock import AT25010B_EEPROM
from cocotb_tools.runner import get_runner

# ──────────────────────────────────────────────────────────────────────────────
# Constants matching eeprom_spi / axi_spi_master configuration
# ──────────────────────────────────────────────────────────────────────────────
CLK_PERIOD_NS = 350  # 2.8 Mhz
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
        cs_name="spi_csn1",
    )


async def reset_dut(dut):
    """Assert reset for RESET_CYCLES, then release and wait for init."""
    dut.rst_n.value = 0
    dut.cmd_valid.value = 0
    dut.cmd_write.value = 0
    dut.cmd_addr.value = 0
    dut.cmd_wdata.value = 0

    for _ in range(RESET_CYCLES):
        await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    # Wait for the one-time SPI clock-divider init to complete.
    # The eeprom_spi FSM starts in S_INIT_CLKDIV and transitions to S_IDLE
    # after the AXI write finishes (~8-10 cycles).  cmd_busy is NOT asserted
    # during init states, but we need to let the AXI transaction finish so
    # the SPI clock divider is properly configured before any user commands.
    for _ in range(50):
        await RisingEdge(dut.clk)


async def send_cmd(dut, *, write: bool, addr: int, wdata: int = 0) -> None:
    """
    Drive a one-cycle cmd_valid pulse to start a transaction.

    The caller must then wait for cmd_done (use wait_done()).
    """
    dut.cmd_write.value = int(write)
    dut.cmd_addr.value = addr & 0x7F
    dut.cmd_wdata.value = wdata & 0xFF
    dut.cmd_valid.value = 1
    await RisingEdge(dut.clk)
    dut.cmd_valid.value = 0


async def wait_done(dut, timeout_us: int = TRANSACTION_TIMEOUT_US) -> None:
    """
    Block until cmd_done pulses high, or raise TestFailure on timeout.
    """
    timeout_trigger = Timer(timeout_us, "us")
    done_trigger = RisingEdge(dut.cmd_done)

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
            f"Timed out after {timeout_us} µs waiting for cmd_done. "
            f"FSM state={fsm_state}, cmd_busy={int(dut.cmd_busy.value)}, "
            f"axi_busy={axi_busy}"
        )
    # cmd_done is a single-cycle pulse; make sure we sampled it on a rising edge
    await RisingEdge(dut.clk)


async def eeprom_write(dut, addr: int, data: int) -> None:
    """Issue a write command and wait for completion."""
    await send_cmd(dut, write=True, addr=addr, wdata=data)
    await wait_done(dut)


async def eeprom_read(dut, addr: int) -> int:
    """Issue a read command, wait for completion, return cmd_rdata."""
    await send_cmd(dut, write=False, addr=addr)
    await wait_done(dut)
    return int(dut.cmd_rdata.value)


# ──────────────────────────────────────────────────────────────────────────────
# Common fixture: start clock + reset + attach EEPROM mock
# ──────────────────────────────────────────────────────────────────────────────


async def setup(dut) -> AT25010B_EEPROM:
    """
    Start the simulation clock, reset the DUT, and attach the EEPROM mock.
    Returns the mock so tests can pre-load / inspect memory.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    eeprom = AT25010B_EEPROM(build_spi_bus(dut))
    await reset_dut(dut)
    return eeprom


# ══════════════════════════════════════════════════════════════════════════════
# Tests
# ══════════════════════════════════════════════════════════════════════════════


# ── 1. Sanity: DUT comes out of reset in IDLE ─────────────────────────────────
@cocotb.test()
async def test_reset_state(dut):
    """After reset, cmd_busy must be low and cmd_done must be low."""
    await setup(dut)
    await RisingEdge(dut.clk)

    assert int(dut.cmd_busy.value) == 0, "cmd_busy should be 0 after reset"
    assert int(dut.cmd_done.value) == 0, "cmd_done should be 0 after reset"


# ── 2. Basic read from a known address ───────────────────────────────────────
@cocotb.test()
async def test_read_basic(dut):
    """
    Pre-load EEPROM[0x10] = 0xAB.
    Issue a read at address 0x10.
    Expect cmd_rdata == 0xAB and cmd_done to pulse.
    """
    eeprom = await setup(dut)
    eeprom.memory[0x10] = 0xAB

    rdata = await eeprom_read(dut, addr=0x10)

    assert rdata == 0xAB, f"Expected 0xAB, got {rdata:#04x}"
    assert int(dut.cmd_busy.value) == 0, "FSM should return to IDLE after read"


# ── 3. Basic write then read-back ─────────────────────────────────────────────
@cocotb.test()
async def test_write_then_read(dut):
    """
    Write 0xDE to address 0x05.
    Read it back; expect 0xDE.
    """
    eeprom = await setup(dut)

    await eeprom_write(dut, addr=0x05, data=0xDE)

    # Confirm the mock received the write
    assert eeprom.memory[0x05] == 0xDE, (
        f"EEPROM mock did not store the written byte; "
        f"memory[0x05]={eeprom.memory[0x05]:#04x}"
    )

    rdata = await eeprom_read(dut, addr=0x05)
    assert rdata == 0xDE, f"Read-back mismatch: expected 0xDE, got {rdata:#04x}"


# ── 4. Write to address 0x00 and read back ───────────────────────────────────
@cocotb.test()
async def test_write_read_address_zero(dut):
    """Boundary: address 0x00 is valid and must be addressable."""
    eeprom = await setup(dut)

    await eeprom_write(dut, addr=0x00, data=0x01)
    assert eeprom.memory[0x00] == 0x01

    rdata = await eeprom_read(dut, addr=0x00)
    assert rdata == 0x01, f"Expected 0x01, got {rdata:#04x}"


# ── 5. Write to top address 0x7F and read back ───────────────────────────────
@cocotb.test()
async def test_write_read_top_address(dut):
    """Boundary: address 0x7F (127) is the last valid EEPROM byte."""
    eeprom = await setup(dut)

    await eeprom_write(dut, addr=0x7F, data=0xFF)
    assert eeprom.memory[0x7F] == 0xFF

    rdata = await eeprom_read(dut, addr=0x7F)
    assert rdata == 0xFF, f"Expected 0xFF, got {rdata:#04x}"


# ── 6. Multiple sequential writes across different addresses ──────────────────
@cocotb.test()
async def test_sequential_writes(dut):
    """
    Write a pattern across 8 addresses, read them all back.
    Verifies the FSM returns to IDLE between transactions.
    """
    eeprom = await setup(dut)
    pattern = {
        0x00: 0x11,
        0x01: 0x22,
        0x10: 0x33,
        0x20: 0x44,
        0x3F: 0x55,
        0x40: 0x66,
        0x60: 0x77,
        0x7F: 0x88,
    }

    for addr, data in pattern.items():
        await eeprom_write(dut, addr=addr, data=data)
        # FSM must be IDLE before next command
        assert (
            int(dut.cmd_busy.value) == 0
        ), f"FSM still busy after write to {addr:#04x}"

    for addr, expected in pattern.items():
        rdata = await eeprom_read(dut, addr=addr)
        assert (
            rdata == expected
        ), f"Address {addr:#04x}: expected {expected:#04x}, got {rdata:#04x}"


# ── 7. cmd_busy is asserted for the duration of a transaction ─────────────────
@cocotb.test()
async def test_cmd_busy_during_transaction(dut):
    """
    cmd_busy must be high from cmd_valid until cmd_done.
    Sample it a few cycles after issuing the command.
    """
    eeprom = await setup(dut)
    eeprom.memory[0x30] = 0xCC

    await send_cmd(dut, write=False, addr=0x30)

    # Give the FSM one cycle to latch the command and assert busy
    await RisingEdge(dut.clk)
    assert (
        int(dut.cmd_busy.value) == 1
    ), "cmd_busy should be high while transaction is in progress"

    await wait_done(dut)
    assert int(dut.cmd_busy.value) == 0, "cmd_busy should deassert after done"


# ── 8. cmd_done is a single-cycle pulse ───────────────────────────────────────
@cocotb.test()
async def test_cmd_done_is_one_cycle_pulse(dut):
    """
    cmd_done must be high for exactly one clock cycle.
    Check the cycle after it fires that it has gone low again.
    """
    eeprom = await setup(dut)
    eeprom.memory[0x20] = 0x55

    await send_cmd(dut, write=False, addr=0x20)
    await wait_done(dut)

    # wait_done already advanced one edge after done; sample cmd_done now
    # It should have returned to 0 (the FSM transitions S_DONE → S_IDLE in one cycle)
    await RisingEdge(dut.clk)
    assert (
        int(dut.cmd_done.value) == 0
    ), "cmd_done should be a single-cycle pulse, but it is still high"


# ── 9. Write all-zeros, verify mock updated ───────────────────────────────────
@cocotb.test()
async def test_write_all_zeros(dut):
    """
    Pre-load 0xFF, then write 0x00; confirm the zero is stored and read back.
    """
    eeprom = await setup(dut)
    eeprom.memory[0x08] = 0xFF  # sentinel

    await eeprom_write(dut, addr=0x08, data=0x00)
    assert eeprom.memory[0x08] == 0x00, "Mock should reflect the written 0x00"

    rdata = await eeprom_read(dut, addr=0x08)
    assert rdata == 0x00, f"Expected 0x00, got {rdata:#04x}"


# ── 10. Write all-ones ────────────────────────────────────────────────────────
@cocotb.test()
async def test_write_all_ones(dut):
    eeprom = await setup(dut)

    await eeprom_write(dut, addr=0x09, data=0xFF)
    rdata = await eeprom_read(dut, addr=0x09)
    assert rdata == 0xFF, f"Expected 0xFF, got {rdata:#04x}"


# ── 11. Read from uninitialised (zero) memory ────────────────────────────────
@cocotb.test()
async def test_read_uninitialised(dut):
    """
    Fresh mock has memory[*] = 0x00.
    A read must return 0x00, and cmd_done must still fire.
    """
    eeprom = await setup(dut)
    # Do NOT pre-load anything

    rdata = await eeprom_read(dut, addr=0x40)
    assert rdata == 0x00, f"Expected 0x00, got {rdata:#04x}"


# ── 12. Back-to-back transactions (no idle gap) ───────────────────────────────
@cocotb.test()
async def test_back_to_back_transactions(dut):
    """
    Issue the next cmd_valid on the very same cycle that cmd_done fires.
    The FSM transitions S_DONE → S_IDLE in one cycle; cmd_valid must be
    accepted in S_IDLE on the next cycle.
    """
    eeprom = await setup(dut)
    eeprom.memory[0x01] = 0xAA
    eeprom.memory[0x02] = 0xBB

    # First read
    await send_cmd(dut, write=False, addr=0x01)

    # Wait for done but queue the second command immediately after
    await wait_done(dut)
    dut.cmd_write.value = 0
    dut.cmd_addr.value = 0x02
    dut.cmd_valid.value = 1
    await RisingEdge(dut.clk)
    dut.cmd_valid.value = 0

    await wait_done(dut)

    rdata = int(dut.cmd_rdata.value)
    assert rdata == 0xBB, f"Back-to-back second read: expected 0xBB, got {rdata:#04x}"


# ── 13. Write does not modify a different address ────────────────────────────
@cocotb.test()
async def test_write_does_not_clobber_neighbours(dut):
    """
    Pre-load 0xAA at 0x10 and 0xBB at 0x12.
    Write 0xFF to 0x11.
    Confirm 0x10 and 0x12 are untouched.
    """
    eeprom = await setup(dut)
    eeprom.memory[0x10] = 0xAA
    eeprom.memory[0x12] = 0xBB

    await eeprom_write(dut, addr=0x11, data=0xFF)

    assert eeprom.memory[0x10] == 0xAA, "Address 0x10 should be unchanged"
    assert eeprom.memory[0x12] == 0xBB, "Address 0x12 should be unchanged"


# ── 14. Overwrite the same address twice ────────────────────────────────────
@cocotb.test()
async def test_overwrite(dut):
    """Second write to the same address must replace the first value."""
    eeprom = await setup(dut)

    await eeprom_write(dut, addr=0x50, data=0x11)
    await eeprom_write(dut, addr=0x50, data=0x99)

    rdata = await eeprom_read(dut, addr=0x50)
    assert rdata == 0x99, f"Expected 0x99 after overwrite, got {rdata:#04x}"


# ── 15. Stress: write/read all 128 addresses ─────────────────────────────────
@cocotb.test()
async def test_full_address_space(dut):
    """
    Write addr XOR 0x55 to every address (0x00–0x7F), then read all back.
    This exercises the full 7-bit address space.
    """
    eeprom = await setup(dut)

    for addr in range(128):
        data = (addr ^ 0x55) & 0xFF
        await eeprom_write(dut, addr=addr, data=data)

    for addr in range(128):
        expected = (addr ^ 0x55) & 0xFF
        rdata = await eeprom_read(dut, addr=addr)
        assert (
            rdata == expected
        ), f"Address {addr:#04x}: expected {expected:#04x}, got {rdata:#04x}"


# -- Runner --


def test_eeprom_spi_e2e_runner():
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
        src_dir / "eeprom_spi.sv",
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
        spi_module_path / "test" / "test_AT25010B_EEPROM" / "eeprom_wire_modules.sv",
    ]

    # Filter out any files that don't exist (in case PULP naming differs)
    sources = [s for s in sources if s.exists()]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="eeprom_wire_modules",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="eeprom_wire_modules",
        test_module="test_eeprom_e2e",
        waves=True,
    )


if __name__ == "__main__":
    test_eeprom_spi_e2e_runner()
