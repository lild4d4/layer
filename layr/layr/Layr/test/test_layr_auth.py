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


async def reset(dut):
    """Apply reset pulse."""
    dut.generate_challenge.value = 0
    dut.verify_id.value = 0
    dut.card_cipher.value = 0
    dut.id_cipher.value = 0

    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_generating_multiple_challenges(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    for _ in range(3):
        dut.card_cipher.value = 0x1234
        dut.generate_challenge.value = 1
        for _ in range(20):
            await RisingEdge(dut.clk)

        assert dut.chip_challenge_generated.value == 1, (
            "Expected the challenge to be generated"
        )
        assert dut.chip_challenge.value == 0x1234 + 42, (
            "Expected card_cipher + 42 (from mock impl)"
        )

        await reset(dut)
        assert dut.chip_challenge_generated.value == 0, (
            "Expected the challenge generated to be reset"
        )
        assert dut.chip_challenge.value == 0, "Expected challenge to be reset"


@cocotb.test()
async def test_verify_id_sets_flags(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for _ in range(2):
        await reset(dut)

        dut.id_cipher.value = 42
        dut.verify_id.value = 1
        await RisingEdge(dut.clk)
        dut.verify_id.value = 0

        for _ in range(20):
            await RisingEdge(dut.clk)

        assert dut.id_verified.value == 1, "Expected ID to be verified"
        assert dut.id_valid.value == 1, "Expected ID to be reported valid"


@cocotb.test()
async def test_challenge_then_verify_id(dut):
    """Generate a challenge first, then verify ID using a separate request."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # First generate a challenge
    dut.card_cipher.value = 0x1234
    dut.generate_challenge.value = 1
    await RisingEdge(dut.clk)
    dut.generate_challenge.value = 0

    for _ in range(20):
        await RisingEdge(dut.clk)

    assert dut.chip_challenge_generated.value == 1, (
        "Expected the challenge to be generated before verify_id"
    )

    # Now verify the ID
    dut.id_cipher.value = 42
    dut.verify_id.value = 1
    await RisingEdge(dut.clk)
    dut.verify_id.value = 0

    for _ in range(20):
        await RisingEdge(dut.clk)

    assert dut.id_verified.value == 1, "Expected ID to be verified after verify_id"
    assert dut.id_valid.value == 1, "Expected ID to be valid after verify_id"


def test_layr_auth_controller_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    root = proj_path / "src"
    sources = [p for p in root.rglob("*") if p.is_file()]
    mocks = proj_path / "test" / "mocks"
    sources += [p for p in mocks.rglob("*") if p.is_file()]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="layr_auth",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        verbose=True,
    )

    runner.test(hdl_toplevel="layr_auth", test_module="test_layr_auth", waves=True)


if __name__ == "__main__":
    test_layr_auth_controller_runner()
