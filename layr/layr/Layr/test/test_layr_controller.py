"""
Modern cocotb 2.0 testbench for the Controller module.
Uses async/await syntax and modern pythonic patterns.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, NextTimeStep, ReadOnly

from cocotb_tools.runner import get_runner

os.environ["COCOTB_ANSI_OUTPUT"] = "1"

outputs = [
    "select_prog",
    "auth_init",
    "generate_challenge",
    "auth",
    "get_id",
    "verify_id",
]

expected = {
    "READY": [],
    "SELECT_PROG": ["select_prog"],
    "AUTH_INIT": ["auth_init"],
    "GENERATE_CHALLENGE": ["generate_challenge"],
    "AUTH": ["auth"],
    "GET_ID": ["get_id"],
    "VERIFY_ID": ["verify_id"],
}


class ControllerTester:
    """Helper class for Controller module testing."""

    def __init__(self, dut):
        self.dut = dut

    async def check_outputs(self, state):
        await ReadOnly()
        await NextTimeStep()
        for output in outputs:
            if output in expected[state]:
                assert getattr(self.dut, output).value == 1, (
                    f"expected output '{output}' to be high in state {state}"
                )
            else:
                assert getattr(self.dut, output).value == 0, (
                    f"expected output '{output}' to be low in state {state}"
                )


async def reset(dut):
    """Apply reset pulse."""
    dut.start.value = 0
    dut.auth_initialized.value = 0
    dut.challenge_generated.value = 0
    dut.authed.value = 0
    dut.id_retrieved.value = 0

    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_full(dut):
    """Test: verify happy path."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    tester = ControllerTester(dut)
    await tester.check_outputs("READY")

    dut.start.value = 1
    await RisingEdge(dut.clk)
    await tester.check_outputs("SELECT_PROG")
    dut.start.value = 0

    dut.prog_selected.value = 1
    await RisingEdge(dut.clk)
    await tester.check_outputs("AUTH_INIT")
    dut.prog_selected.value = 0

    dut.auth_initialized.value = 1
    await RisingEdge(dut.clk)
    await tester.check_outputs("GENERATE_CHALLENGE")
    dut.auth_initialized.value = 0

    dut.challenge_generated.value = 1
    await RisingEdge(dut.clk)
    await tester.check_outputs("AUTH")
    dut.challenge_generated.value = 0

    dut.authed.value = 1
    await RisingEdge(dut.clk)
    await tester.check_outputs("GET_ID")
    dut.authed.value = 0

    dut.id_retrieved.value = 1
    await RisingEdge(dut.clk)
    await tester.check_outputs("VERIFY_ID")
    dut.id_retrieved.value = 0

    dut._log.info("✓ Full test passed")


def test_layr_controller_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [proj_path / "src" / "layr_controller.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="layr_controller",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        verbose=True,
    )

    runner.test(
        hdl_toplevel="layr_controller", test_module="test_layr_controller", waves=True
    )


if __name__ == "__main__":
    test_layr_controller_runner()
