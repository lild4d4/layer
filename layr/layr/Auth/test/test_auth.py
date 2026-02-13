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

os.environ["COCOTB_ANSI_OUTPUT"] = "1"


class AuthInitTester:
    """Helper class for auth_init testing."""

    def __init__(self, dut):
        self.dut = dut

        # Inputs
        self.clk = dut.clk
        self.rst = dut.rst

        # Outputs
        self.aes_cs_o = dut.aes_cs_o
        self.aes_we_o = dut.aes_we_o
        self.aes_address_o = dut.aes_address_o
        self.aes_write_data_o = dut.aes_write_data_o

        # Relevant internal registers
        self.current_state = dut.current_state
        self.key_index = dut.key_index
        self.reg_key = dut.reg_key


class AuthGenerateChallengeTester:
    """Helper class for auth_generate_challenge testing."""

    def __init__(self, dut):
        self.dut = dut

        # Inputs
        self.clk = dut.clk
        self.rst = dut.rst
        self.external_ready_i = dut.external_ready_i
        self.external_valid_i = dut.external_valid_i
        self.input_cipher_i = dut.input_cipher_i

        # Outputs
        self.error_o = dut.error_o
        self.internal_ready_o = dut.internal_ready_o
        self.internal_valid_o = dut.internal_valid_o
        self.challenge_response_o = dut.challenge_response_o


class AuthVerifyIdTester:
    """Helper class for auth_verify_id testing."""

    def __init__(self, dut):
        self.dut = dut

        # Inputs
        self.clk = dut.clk
        self.rst = dut.rst
        self.external_valid_i = dut.external_valid_i
        self.id_cipher_i = dut.id_cipher_i
        self.rc_i = dut.rc_i
        self.rt_i = dut.rt_i

        # Outputs
        self.error_o = dut.error_o
        self.success_o = dut.success_o
        self.internal_ready_o = dut.internal_ready_o


async def start_clock(dut, period_ns=10):
    """Spawn a 100+MHz clock on dut.clk."""
    cocotb.start_soon(Clock(dut.clk, period_ns, unit="ns").start())


async def reset_dut(tester, cycles=2):
    """Apply an active‑high reset for *cycles* clock edges."""
    tester.rst.value = 1
    for _ in range(cycles):
        await RisingEdge(tester.clk)
    tester.rst.value = 0
    # Give the design one more edge to come out of reset cleanly
    await RisingEdge(tester.clk)


@cocotb.test()
async def auth_init__write_key_to_aes_core(dut):
    """Test: Check key write to aes core"""
    tester = AuthInitTester(dut)
    await start_clock(dut)
    await reset_dut(tester)

    while True:
        await RisingEdge(tester.clk)

        if int(tester.current_state.value) == 1:
            break

    written_data = []
    while True:
        await RisingEdge(tester.clk)

        if int(tester.current_state.value) == 0:
            break

        if tester.aes_cs_o.value == 1 and tester.aes_we_o.value == 1:
            written_data.append((
                tester.aes_address_o.value,
                tester.aes_write_data_o.value
            ))

    assert len(written_data) == 4, f"Expected 8 key‑word writes, but saw {len(written_data)}."

    for idx, (address, key_fragment) in enumerate(written_data):
        expected_address = 0x10 + idx
        expected_key_fragment = 10 + idx

        assert address == expected_address, (
            f"Key word {idx}: address mismatch – got {address}, "
            f"expected {bin(expected_address)}"
        )

        assert key_fragment == expected_key_fragment, (
            f"Key word {idx}: key fragment mismatch – got {key_fragment}, "
            f"expected {bin(expected_key_fragment)}"
        )


def test_auth():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path / "src" / "auth_init.sv",
        proj_path / "src" / "auth_generate_challenge.sv",
        proj_path / "src" / "auth_verify_id.sv",
        proj_path / "secworks-aes" / "src" / "rtl" / "aes.v",
        proj_path / "secworks-aes" / "src" / "rtl" / "aes_core.v",
        proj_path / "secworks-aes" / "src" / "rtl" / "aes_decipher_block.v",
        proj_path / "secworks-aes" / "src" / "rtl" / "aes_encipher_block.v",
        proj_path / "secworks-aes" / "src" / "rtl" / "aes_inv_sbox.v",
        proj_path / "secworks-aes" / "src" / "rtl" / "aes_key_mem.v",
        proj_path / "secworks-aes" / "src" / "rtl" / "aes_sbox.v",
    ]

    auth_init_runner = get_runner(sim)

    auth_init_runner.build(
        sources=sources,
        hdl_toplevel="auth_init",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    auth_init_runner.test(
        hdl_toplevel="auth_init", test_module="test_auth", waves=True
    )


if __name__ == "__main__":
    test_auth()
