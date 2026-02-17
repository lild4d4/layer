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
    dut.start_i.value = 1
    dut.eeprom_busy.value = 0
    dut.eeprom_done.value = 1
    dut.eeprom_buffer.value = int.from_bytes(key);

    while True:
        await RisingEdge(dut.clk)

        if dut.u_auth_challenge.u_aes_handler.valid.value == 1:
            dut.start_i.value = 0
            await RisingEdge(dut.clk)
            break

    assert dut.u_aes_core.result.value == int.from_bytes(plain)


@cocotb.test()
async def auth_challenge__full_flow(dut):
    key = b'\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c'
    plain = b'\x11\x11\xca\xfe\xaf\xfe\x11\x11\x00\x00\x00\x00\x00\x00\x00\x00'
    rc = plain[:8]
    cipher = AES.new(key, AES.MODE_ECB)
    ciphertext = cipher.encrypt(plain)

    await start_clock(dut)
    await reset_dut(dut)

    dut.operation_i.value = 0
    dut.data_i.value = int.from_bytes(ciphertext)
    dut.start_i.value = 1
    dut.eeprom_busy.value = 0
    dut.eeprom_done.value = 1
    dut.eeprom_buffer.value = int.from_bytes(key);

    while True:
        await RisingEdge(dut.clk)

        if dut.u_auth_challenge.u_random.valid.value == 1:
            rt = int(dut.u_auth_challenge.rt.value).to_bytes(8)

        if dut.valid_o.value == 1:
            dut.start_i.value = 0
            challenge = dut.data_o.value
            await RisingEdge(dut.clk)
            break

    challenge_raw = rt + rc
    session_key_raw = rc + rt
    challenge = cipher.encrypt(challenge_raw)
    session_key = cipher.encrypt(session_key_raw)

    assert dut.data_o.value == int.from_bytes(challenge), f"challenge value mismatch: {hex(dut.data_o.value)} != {hex(int.from_bytes(challenge))}"
    assert dut.u_auth_challenge.session_key.value == int.from_bytes(session_key), f"session key mismatch: {dut.u_auth_challenge.session_key.value} != {hex(int.from_bytes(session_key))}"


@cocotb.test()
async def auth_verify_id__valid_id(dut):
    session_key = b'\xff\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c'
    card_b_id = b'\xd0\xd2\x3f\x18\x25\x1c\x60\x87\x56\x6d\xe7\xb7\xde\xab\x77\x74'
    cipher = AES.new(session_key, AES.MODE_ECB)
    ciphertext = cipher.encrypt(card_b_id)

    await start_clock(dut)
    await reset_dut(dut)

    dut.operation_i.value = 1
    dut.data_i.value = int.from_bytes(ciphertext)
    dut.session_key.value = int.from_bytes(session_key)
    dut.start_i.value = 1
    dut.eeprom_busy.value = 1
    dut.eeprom_done.value = 0
    dut.u_auth_verify_id.eeprom_start.value = 0

    id_validated = 0
    id_validated_output = 0
    while True:
        await RisingEdge(dut.clk)

        # Get key after reset
        if dut.state.value == 1:
            dut._log.info("ok")
            dut.eeprom_done.value = 1
            await RisingEdge(dut.clk)
            dut.eeprom_done.value = 0

        if dut.u_auth_verify_id.state.value == 2:
            # Wait two cycles while eeprom is still "busy"
            for _ in range(2): await RisingEdge(dut.clk)
            dut.eeprom_busy.value = 0

            await RisingEdge(dut.clk)
            assert int(dut.eeprom_start.value) == 1, "Did not started EEPROM"

            await RisingEdge(dut.clk)
            dut.eeprom_busy.value = 1

            # Wait another few cycles, then provide a result
            for _ in range(3): await RisingEdge(dut.clk)
            dut.eeprom_buffer.value = int.from_bytes(card_b_id)
            dut.eeprom_busy.value = 0
            dut.eeprom_done.value = 1
            await RisingEdge(dut.clk)

        if dut.valid_o.value == 1:
            dut.start_i.value = 0
            id_validated = dut.u_auth_verify_id.id_valid.value
            id_validated_output = dut.data_o.value[0]
            await RisingEdge(dut.clk)
            break

    assert id_validated == 1, "Valid ID was marked as invalid."
    assert id_validated_output == 1, "Valid status was not correctly output."


@cocotb.test()
async def auth_verify_id__invalid_id(dut):
    session_key = b'\xff\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c'
    card_b_id = b'\xd0\xd2\x3f\x18\x25\x1c\x60\x87\x56\x6d\xe7\xb7\xde\xab\x77\x74'
    cipher = AES.new(session_key, AES.MODE_ECB)
    ciphertext = cipher.encrypt(card_b_id)

    await start_clock(dut)
    await reset_dut(dut)

    dut.operation_i.value = 1
    dut.data_i.value = int.from_bytes(ciphertext)
    dut.session_key.value = int.from_bytes(session_key)
    dut.start_i.value = 1
    dut.eeprom_busy.value = 1
    dut.eeprom_done.value = 0
    dut.u_auth_verify_id.eeprom_start.value = 0

    id_validated = 0
    id_validated_output = 0
    while True:
        await RisingEdge(dut.clk)

        # Get key after reset
        if dut.state.value == 1:
            dut._log.info("ok")
            dut.eeprom_done.value = 1
            await RisingEdge(dut.clk)
            dut.eeprom_done.value = 0

        if dut.u_auth_verify_id.state.value == 2:
            # Wait two cycles while eeprom is still "busy"
            for _ in range(2): await RisingEdge(dut.clk)
            dut.eeprom_busy.value = 0

            await RisingEdge(dut.clk)
            assert int(dut.eeprom_start.value) == 1, "Did not request ID from eeprom"

            await RisingEdge(dut.clk)
            dut.eeprom_busy.value = 1

            # Wait another few cycles, then provide a result
            for _ in range(3): await RisingEdge(dut.clk)
            dut.eeprom_buffer.value = int.from_bytes(card_b_id[:15] + b'\xff')
            dut.eeprom_busy.value = 0
            dut.eeprom_done.value = 1
            await RisingEdge(dut.clk)

        if dut.valid_o.value == 1:
            dut.start_i.value = 0
            id_validated = dut.u_auth_verify_id.id_valid.value
            id_validated_output = dut.data_o.value[0]
            await RisingEdge(dut.clk)
            break

    assert id_validated == 0, "Valid ID was marked as invalid."
    assert id_validated_output == 0, "Valid status was not correctly output."


def test_auth():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path / "src" / "auth.sv",
        proj_path / "src" / "auth_challenge.sv",
        proj_path / "src" / "auth_aes_handler.sv",
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
