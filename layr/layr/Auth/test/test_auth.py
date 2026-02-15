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


class AuthInitTester:
    """Helper class for auth_init testing."""

    def __init__(self, dut):
        self.dut = dut

        # Inputs
        self.clk = dut.init.clk
        self.rst = dut.init.rst

        # Outputs
        self.init_done = dut.init.init_done
        self.aes_cs_o = dut.init.aes_cs_o
        self.aes_we_o = dut.init.aes_we_o
        self.aes_address_o = dut.init.aes_address_o
        self.aes_write_data_o = dut.init.aes_write_data_o

        # Relevant internal registers
        self.state = dut.init.state
        self.key_index = dut.init.key_index
        self.reg_key = dut.init.reg_key

class AuthDecryptTester:
    """Helper class for auth_generate_challenge testing."""

    def __init__(self, dut):
        self.dut = dut

        # Inputs
        self.clk = dut.generate_challenge.decrypt.clk
        self.rst = dut.generate_challenge.decrypt.rst
        self.start_i = dut.generate_challenge.decrypt.start_i
        self.aes_read_data_i = dut.generate_challenge.decrypt.aes_read_data_i
        self.input_cipher_i = dut.generate_challenge.decrypt.input_cipher_i

        # Outputs
        self.aes_cs_o = dut.generate_challenge.decrypt.aes_cs_o
        self.aes_we_o = dut.generate_challenge.decrypt.aes_we_o
        self.aes_address_o = dut.generate_challenge.decrypt.aes_address_o
        self.aes_write_data_o = dut.generate_challenge.decrypt.aes_write_data_o
        self.rc = dut.generate_challenge.decrypt.rc
        self.valid_o = dut.generate_challenge.decrypt.valid_o

        # Internal registers
        self.state = dut.generate_challenge.decrypt.state
        self.next_state = dut.generate_challenge.decrypt.next_state


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
async def auth_init__write_key_to_aes_core(dut):
    """Test: Check key write to aes core"""
    tester = AuthInitTester(dut)
    await start_clock(dut)
    await reset_dut(dut)

    while True:
        await RisingEdge(tester.clk)

        if int(tester.state.value) == 1:
            break

    written_data = []
    while True:
        await RisingEdge(tester.clk)

        if int(tester.state.value) == 0:
            break

        if tester.aes_cs_o.value == 1 and tester.aes_we_o.value == 1:
            written_data.append((
                tester.aes_address_o.value,
                tester.aes_write_data_o.value
            ))

    assert len(written_data) == 4, f"Expected 8 key‑word writes, but saw {len(written_data)}."

    for idx, (address, key_fragment) in enumerate(written_data):
        expected_address = 0x10 + idx
        expected_key_fragment = 0x0a + idx

        assert address == expected_address, (
            f"Key word {idx}: address mismatch – got {address}, "
            f"expected {bin(expected_address)}"
        )

        assert key_fragment == expected_key_fragment, (
            f"Key word {idx}: key fragment mismatch – got {key_fragment}, "
            f"expected {bin(expected_key_fragment)}"
        )

    expected_core_key = '0' * 128 +\
                        '0' * 24 + '00001010' +\
                        '0' * 24 + '00001011' +\
                        '0' * 24 + '00001100' +\
                        '0' * 24 + '00001101'

    await RisingEdge(tester.clk)
    assert expected_core_key == str(dut.aes.core_key.value), "AES core_key is mismatch."


@cocotb.test()
async def auth_decrypt__decrypt_input_cipher(dut):
    tester = AuthDecryptTester(dut)

    key = b'\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c'
    plain = b'\x6b\xc1\xbe\xe2\x2e\x40\x9f\x96\xe9\x3d\x7e\x11\x73\x93\x17\x2a'

    cipher = AES.new(key, AES.MODE_ECB)
    ciphertext = cipher.encrypt(plain)

    dut._log.info(f"Using cipher: {hex(int.from_bytes(ciphertext))}")

    await start_clock(dut)
    await reset_dut(dut)

    tester.input_cipher_i.value = int.from_bytes(ciphertext)
    dut.start_i.value = 1
    await RisingEdge(tester.clk)

    counter = 0
    while True:
        await RisingEdge(tester.clk)

        if tester.valid_o.value == 1:
            dut.start_i.value = 0
            break

        counter += 1
        if counter == 1000:
            break


    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert tester.rc.value == int.from_bytes(plain), "Decrypted rc is different from original rc."


def test_auth():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path / "src" / "auth.sv",
        proj_path / "src" / "auth_init.sv",
        proj_path / "src" / "auth_generate_challenge.sv",
        proj_path / "src" / "auth_decrypt.sv",
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
