"""
Modern cocotb 2.0 testbench for the Controller module.
Uses async/await syntax and modern pythonic patterns.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, FallingEdge, NextTimeStep, ReadOnly
from cocotb.types import LogicArray

from cocotb_tools.runner import get_runner

os.environ['COCOTB_ANSI_OUTPUT'] = '1'

class BCDConverterTester:
    """Helper class for BCD module testing."""

    def __init__(self, dut):
        self.dut = dut
        self.binary = dut.binary
        self.tens = dut.tens
        self.ones = dut.ones

    async def set_binary(self, value: int):
        """Set binary input value."""
        await NextTimeStep()
        await ReadOnly()

@cocotb.test()
async def test_all_values(dut):
    """Test: Iterate through all binary values from 0 to 31 and check BCD outputs."""
    tester = BCDConverterTester(dut)
    
    # Test all values from 0 to 31
    for value in range(32):
        tester.binary.value = value
        expected_tens = value // 10
        expected_ones = value % 10

        await Timer(1, unit='ns')  # Wait for outputs to stabilize

        dut._log.info(f"Checking value {value}: expected tens {expected_tens}, expected ones {expected_ones}")        

        assert tester.tens.value == expected_tens, f"Failed for value {value}: expected tens {expected_tens}, got {tester.tens.value}"
        assert tester.ones.value == expected_ones, f"Failed for value {value}: expected ones {expected_ones}, got {tester.ones.value}"

    dut._log.info("✓ Full test passed")


def test_bcd_converter_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [proj_path / "src" / "bcd_converter.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="bcd_converter",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(hdl_toplevel="bcd_converter", test_module="test_bcd_converter", waves=True)

if __name__ == "__main__":
    test_bcd_converter_runner()