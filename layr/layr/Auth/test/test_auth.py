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

from Crypto.Cipher import AES

os.environ["COCOTB_ANSI_OUTPUT"] = "1"


class AuthDecryptTester:
    """Helper class for auth_generate_challenge testing."""

    def __init__(self, dut):
        self.dut = dut

        # Outputs
        self.valid = dut.u_auth_challenge.u_auth_decrypt.valid


async def start_clock(dut, period_ns=10):
    """Spawn a 100+MHz clock on dut.clk."""
    cocotb.start_soon(Clock(dut.clk, period_ns, unit="ns").start())


async def reset_dut(tester, cycles=2):
    """Apply an active‑high reset for *cycles* clock edges."""
    tester.rst.value = 1
    await RisingEdge(tester.clk)
    tester.rst.value = 0
    await RisingEdge(tester.clk)
    # Give the design one more edge to come out of reset cleanly



@cocotb.test()
async def auth_challenge__decrypt_input_cipher(dut):
    key = b'\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c'
    plain = b'\x6b\xc1\xbe\xe2\x2e\x40\x9f\x96\xe9\x3d\x7e\x11\x73\x93\x17\x2a'
    cipher = AES.new(key, AES.MODE_ECB)
    ciphertext = cipher.encrypt(plain)

    await start_clock(dut)
    await reset_dut(dut)

    dut.operation_i.value = 0
    dut.data_i.value = int.from_bytes(ciphertext)
    dut.u_auth_challenge.input_key.value = int.from_bytes(key);
    dut.start_i.value = 1

    while True:
        await RisingEdge(dut.clk)

        if dut.u_auth_challenge.u_aes_handler.valid.value == 1:
            dut.start_i.value = 0
            await RisingEdge(dut.clk)
            break

    assert dut.u_aes_core.result.value == int.from_bytes(plain)


@cocotb.test()
async def auth_challenge__encrypt_challenge(dut):
    key = b'\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c'
    plain = b'\x11\x11\xca\xfe\xaf\xfe\x11\x11\x00\x00\x00\x00\x00\x00\x00\x00'
    cipher = AES.new(key, AES.MODE_ECB)
    ciphertext = cipher.encrypt(plain)

    await start_clock(dut)
    await reset_dut(dut)

    dut.operation_i.value = 0
    dut.data_i.value = int.from_bytes(ciphertext)
    dut.u_auth_challenge.input_key.value = int.from_bytes(key);
    dut.start_i.value = 1

    while True:
        await RisingEdge(dut.clk)

        if dut.valid_o.value == 1:
            dut.start_i.value = 0
            await RisingEdge(dut.clk)
            break


def test_auth():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path / "src" / "auth.sv",
        proj_path / "src" / "auth_challenge.sv",
        proj_path / "src" / "auth_decrypt.sv",
        proj_path / "src" / "auth_encrypt.sv",
        proj_path / "src" / "auth_random.sv",
        proj_path / "src" / "auth_verify_id.sv",
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
        hdl_toplevel="auth",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    auth_init_runner.test(
        hdl_toplevel="auth", test_module="test_auth", waves=True
    )


if __name__ == "__main__":
    test_auth()
