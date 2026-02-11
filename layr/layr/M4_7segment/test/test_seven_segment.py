"""
Modern cocotb 2.0 testbench for the Controller module.
Uses async/await syntax and modern pythonic patterns.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.types import LogicArray

from cocotb_tools.runner import get_runner
import random

os.environ['COCOTB_ANSI_OUTPUT'] = '1'

class SevenSegmentTester:
    """Helper class for seven segment testing."""

    def __init__(self, dut):
        self.dut = dut
        self.clk = dut.clk
        self.digit = dut.digit
        self.update = dut.update
        self.seg = dut.seg

    async def set_digit(self, value: int, update: bool):
        """Set operand input value."""
        await FallingEdge(self.clk)     
        self.digit.value = value
        self.update.value = update

    async def check_segment(self, expected_value: int):
        """Check the segment output value."""
        await RisingEdge(self.clk)
        display = {
            0: LogicArray("1111110", 7),
            1: LogicArray("0110000", 7),
            2: LogicArray("1101101", 7),
            3: LogicArray("1111001", 7),
            4: LogicArray("0110011", 7),
            5: LogicArray("1011011", 7),
            6: LogicArray("1011111", 7),
            7: LogicArray("1110000", 7),
            8: LogicArray("1111111", 7),
            9: LogicArray("1111011", 7)
        }
        assert self.seg.value == display[expected_value], f"Expected segment {display[expected_value]}, got {self.seg.value}"

@cocotb.test()
async def test_basic_operation(dut):
    """Test: Check the basic functionality"""
    tester = SevenSegmentTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await tester.set_digit(5, update=True)
    await RisingEdge(tester.clk)

    await tester.check_segment(5)
    await RisingEdge(tester.clk)
    await tester.check_segment(5)

    dut._log.info("✓ Basic test passed")

@cocotb.test()
async def test_all(dut):
    """Test: Check the basic functionality"""
    tester = SevenSegmentTester(dut)

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    for i in range(10):
        dut._log.info(f"Testing digit {i}")
        await tester.set_digit(i, update=True)
        await RisingEdge(tester.clk)
        await tester.check_segment(i)

    dut._log.info("✓ Full test passed")

def test_seven_segment_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [proj_path / "src" / "seven_segment.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="seven_segment",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(hdl_toplevel="seven_segment", test_module="test_seven_segment", waves=True)

if __name__ == "__main__":
    test_seven_segment_runner()