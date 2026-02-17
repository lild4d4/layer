"""
Modern cocotb 2.0 testbench for the Controller module.
Uses async/await syntax and modern pythonic patterns.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotb_tools.runner import get_runner

os.environ["COCOTB_ANSI_OUTPUT"] = "1"


class LayrTester:
    """Helper class for Controller module testing."""

    def __init__(self, dut):
        self.dut = dut


async def reset(dut):
    """Apply reset pulse."""
    dut.card_present.value = 0
    dut.response_valid.value = 0
    dut.response.value = 0

    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_happy_path(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    result = await run_validation(dut, 42)
    assert result == 1, "Expected the id to be valid"
    dut._log.info("✓ Full test passed")


async def run_validation(dut, id_cypher):
    dut.card_present.value = 1
    assert dut.command_valid.value == 0

    await await_command_valid(dut, "Select Prog Command")
    assert dut.command.value == 0x00A4040006F000000CDC00, "Expected chip select command"
    await set_response(dut, 24)

    assert dut.command_valid.value == 0
    await await_command_valid(dut, "Auth_Init Command")
    assert dut.command.value == 0x0801000001000000000000000000000000000000000, (
        "Auth init"
    )

    await set_response(dut, 24)
    assert dut.chip_cypher.value == 0, "Expected the challenge not to be set yet"
    assert dut.command_valid.value == 0
    await advance_cycles(dut, 11)
    assert dut.chip_cypher.value == 24 + 42, (
        "Expected the card challenge to be generated"
    )

    await await_command_valid(dut, "Auth Command")
    assert dut.command.value == 0x0801100001000000000000000000000000000000042, "Auth"

    await set_response(dut, 0)

    assert dut.command_valid.value == 0

    await await_command_valid(dut, "Get Id")
    assert dut.command.value == 0x0801200001000000000000000000000000000000000, "Get Id"

    await set_response(dut, id_cypher)

    await await_status_valid(dut)
    result = dut.status.value
    dut.card_present.value = 0
    await advance_cycles(dut, 2)
    return result


async def set_response(dut, value):
    dut.response_valid.value = 1
    dut.response.value = value
    await advance_cycles(dut, 2)
    dut.response.value = 0
    dut.response_valid.value = 0


async def await_command_valid(dut, msg):
    for _ in range(1000):
        await RisingEdge(dut.clk)
        if dut.command_valid.value:
            break
    assert dut.command_valid.value == 1, (
        f"{msg}: did not become valid within the maximum number of time steps"
    )


async def await_status_valid(dut):
    for _ in range(1000):
        await RisingEdge(dut.clk)
        if dut.status_valid.value:
            break
    assert dut.status_valid.value == 1, (
        "did not validate in maximum number of time steps"
    )


async def await_validated(dut, msg):
    for _ in range(1000):
        await RisingEdge(dut.clk)
        if dut.command_valid.value:
            break
    assert dut.command_valid.value == 1, (
        f"{msg}: did not become valid within the maximum number of time steps"
    )


async def advance_cycles(dut, cycles: int):
    """Helper to advance a given number of clock cycles."""
    for _ in range(cycles):
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_no_command_without_card_present(dut):
    """Ensure no command is issued when no card is present."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Keep card absent and let the design run for a few cycles
    dut.card_present.value = 0
    dut.response_valid.value = 0
    await advance_cycles(dut, 5)

    # With no card present, we don't expect a command to be driven
    assert int(dut.command.value) == 0, "Expected no command when card is not present"


@cocotb.test()
async def test_multiple_happy_sessions(dut):
    """Run the happy path multiple times to check stability."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    for i in range(20):
        valid = (i // 5) % 2
        id_cypher = 42 if valid else 48
        result = await run_validation(dut, id_cypher)
        assert result == valid, (
            f"Expected the id_cypher {id_cypher} to be {'valid' if valid else 'invalid'}"
        )


def test_layr_controller_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    root = proj_path / "src"
    mocks = proj_path / "test" / "mocks"
    sources = [p for p in root.rglob("*") if p.is_file()]
    sources += [p for p in mocks.rglob("*") if p.is_file()]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="layr",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        verbose=True,
    )

    runner.test(hdl_toplevel="layr", test_module="test_layr", waves=True)


if __name__ == "__main__":
    test_layr_controller_runner()
