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


@cocotb.test()
async def test_something(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for _ in range(200):
        await RisingEdge(dut.clk)


def test_chip_controller_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent.parent
    chip = proj_path / "Chip" / "src"
    auth = proj_path / "Auth" / "src"
    aes = proj_path / "Auth" / "secworks-aes" / "src" / "rtl"
    layr = proj_path / "Layr" / "src"
    spi = proj_path / "SPI" / "src"

    sources = []
    for folder in [chip, auth, aes, layr, spi]:
        sources += [p for p in folder.rglob("*") if p.is_file()]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="chip",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        verbose=True,
    )

    runner.test(hdl_toplevel="chip", test_module="test_chip", waves=True)


if __name__ == "__main__":
    test_chip_controller_runner()
