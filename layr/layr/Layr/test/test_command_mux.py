import os
from pathlib import Path

import secrets
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


from cocotb_tools.runner import get_runner

os.environ["COCOTB_ANSI_OUTPUT"] = "1"

SETUP_PROG = 0
AUTH_INIT = 1
AUTH = 2
GET_ID = 3


async def reset(dut):
    """Apply reset pulse."""
    dut.auth_init.value = 0
    dut.auth.value = 0
    dut.get_id.value = 0

    dut.response.value = 0
    dut.response_valid.value = 0
    dut.chip_challenge.value = 0

    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_auth_init_transmission(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.auth_init.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.state.value == 1, "Expected the fsm to be in sending state"
    assert dut.active_transmission.value == AUTH_INIT, (
        "Expected active transmission to be of type auth_init"
    )
    assert dut.command.value == 0x0801000001000000000000000000000000000000000
    assert dut.command_valid.value == 1, "Expected the command to be valid"
    assert dut.auth_initialized.value == 0, "Expected that auth_initialized to be low"

    response = int.from_bytes(secrets.token_bytes(16))
    dut.response.value = response
    dut.response_valid.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.state.value == 0, (
        "Expected the fsm to be in ready state - as the command was completed by response from card"
    )
    assert dut.command_valid.value == 0, "Expected the command to be valid"
    assert dut.card_challenge.value == response, (
        "Expected the response to be writte into the chip challenge"
    )
    assert dut.auth_initialized.value == 1, "Expected that auth_initialized to be high"


@cocotb.test()
async def test_transmission_mode_cannot_be_changed_when_running(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    challenge = secrets.token_bytes(16)
    expected = int.from_bytes(
        0x08011000010.to_bytes(5, byteorder="big") + challenge, byteorder="big"
    )

    dut.auth.value = 1
    dut.chip_challenge.value = int.from_bytes(challenge, byteorder="big")
    # todo js check again why here two rising edges are needed
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.state.value == 1, "Expected the fsm to be in sending state"
    assert dut.active_transmission.value == AUTH, (
        "Expected active transmission to be of type auth"
    )
    assert dut.command.value == expected, f"Expected the value to be {bin(expected)}"

    dut.auth_init.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.state.value == 1, "Expected the fsm to still be in sending state"
    assert dut.active_transmission.value == AUTH, (
        "Expected active transmission to still be of type auth"
    )
    assert dut.command.value == expected


@cocotb.test()
async def test_auth_transmission(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    challenge = secrets.token_bytes(16)
    expected = int.from_bytes(
        0x08011000010.to_bytes(5, byteorder="big") + challenge, byteorder="big"
    )

    dut.auth.value = 1
    dut.chip_challenge.value = int.from_bytes(challenge, byteorder="big")
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.state.value == 1, "Expected the fsm to be in sending state"
    assert dut.active_transmission.value == AUTH, (
        "Expected active transmission to be of type auth"
    )
    assert dut.command.value == expected, f"Expected the value to be {bin(expected)}"
    assert dut.command_valid.value == 1, "Expected the command to be valid"
    assert dut.authed.value == 0, "Expected authed to be low"

    response = int.from_bytes(secrets.token_bytes(16))
    dut.response.value = response
    dut.response_valid.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.state.value == 0, (
        "Expected the fsm to be in ready state - as the command was completed by response from card"
    )
    assert dut.command_valid.value == 0, "Expected the command to be valid"
    assert dut.authed.value == 1, "Expected authed to be high"


@cocotb.test()
async def test_get_id_transmission(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.get_id.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.state.value == 1, "Expected the fsm to be in sending state"
    assert dut.active_transmission.value == GET_ID, (
        "Expected active transmission to be of type get_id"
    )
    assert dut.command.value == 0x0801200001000000000000000000000000000000000
    assert dut.command_valid.value == 1, "Expected the command to be valid"
    assert dut.id_retrieved.value == 0, "Expected that the id is not retrieved yet"

    response = int.from_bytes(secrets.token_bytes(16))
    dut.response.value = response
    dut.response_valid.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.state.value == 0, (
        "Expected the fsm to be in ready state - as the command was completed by response from card"
    )
    assert dut.command_valid.value == 0, "Expected the command to be valid"
    assert dut.id_cipher.value == response, (
        "Expected the response to be writte into the id cipher"
    )
    assert dut.id_retrieved.value == 1, "Expected the id to be retrieved"


@cocotb.test()
async def test_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.get_id.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.state.value == 1, "Expected the fsm to be in sending state"
    await reset(dut)
    assert dut.state.value == 0, "Expected to be in ready state"
    assert dut.prog_selected.value == 0, "Expected that the id not to be retireved"
    assert dut.command_valid.value == 0, "Expected command to be not valid"
    assert dut.command.value == 0, "Expected command to be reset"
    assert dut.auth_initialized.value == 0, "Expected the auth not to be initialized"
    assert dut.authed.value == 0, "Expected authed to be reset"
    assert dut.id_retrieved.value == 0, "Expected that the id not to be retireved"


def test_command_mux_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [proj_path / "src" / "command_mux.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="command_mux",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        verbose=True,
    )

    runner.test(hdl_toplevel="command_mux", test_module="test_command_mux", waves=True)


if __name__ == "__main__":
    test_command_mux_runner()
