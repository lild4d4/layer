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
    dut.select_prog.value = 0
    dut.auth_init.value = 0
    dut.auth.value = 0
    dut.get_id.value = 0

    dut.chip_challenge.value = 0

    dut.mfrc_tx_ready.value = 1
    dut.mfrc_rx_valid.value = 0
    dut.mfrc_rx_len.value = 0
    dut.mfrc_rx_data.value = 0
    dut.mfrc_rx_last_bits.value = 0

    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def await_tx_valid(dut, msg: str, *, max_cycles: int = 50):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.mfrc_tx_valid.value):
            return
    assert int(dut.mfrc_tx_valid.value) == 1, (
        f"{msg}: mfrc_tx_valid did not assert within {max_cycles} cycles"
    )


async def send_rx_response(dut, response_u128: int):
    """Pulse RX valid with response in the upper 16 bytes."""
    dut.mfrc_rx_data.value = (int(response_u128) & ((1 << 128) - 1)) << 128
    dut.mfrc_rx_len.value = 15  # 16 bytes (0->1 byte encoding)
    dut.mfrc_rx_last_bits.value = 0
    dut.mfrc_rx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.mfrc_rx_valid.value = 0
    dut.mfrc_rx_data.value = 0
    dut.mfrc_rx_len.value = 0


@cocotb.test()
async def test_auth_init_transmission(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.auth_init.value = 1
    await RisingEdge(dut.clk)
    dut.auth_init.value = 0

    await await_tx_valid(dut, "AUTH_INIT")
    assert dut.state.value in (1, 2), "Expected FSM to have started"
    assert dut.active_transmission.value == AUTH_INIT, (
        "Expected active transmission to be of type auth_init"
    )
    assert int(dut.mfrc_tx_len.value) == 20, "Expected 21-byte frame"
    frame = int(dut.mfrc_tx_data.value) >> 88  # top 21 bytes
    cla = (frame >> 160) & 0xFF
    ins = (frame >> 152) & 0xFF
    assert cla == 0x80
    assert ins == 0x10
    assert int(dut.mfrc_tx_valid.value) == 1
    assert dut.auth_initialized.value == 0, "Expected that auth_initialized to be low"

    response = int.from_bytes(secrets.token_bytes(16))
    await send_rx_response(dut, response)
    await RisingEdge(dut.clk)
    assert dut.state.value == 0, (
        "Expected the fsm to be in ready state - as the command was completed by response from card"
    )
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
    await RisingEdge(dut.clk)
    dut.auth.value = 0

    await await_tx_valid(dut, "AUTH")
    assert dut.state.value in (1, 2), "Expected the fsm to be running"
    assert dut.active_transmission.value == AUTH, (
        "Expected active transmission to be of type auth"
    )
    frame = int(dut.mfrc_tx_data.value) >> 88
    assert frame == expected, f"Expected the value to be {bin(expected)}"

    dut.auth_init.value = 1
    await RisingEdge(dut.clk)
    dut.auth_init.value = 0
    assert dut.state.value in (1, 2), "Expected the fsm to still be busy"
    assert dut.active_transmission.value == AUTH, (
        "Expected active transmission to still be of type auth"
    )
    frame2 = int(dut.mfrc_tx_data.value) >> 88
    assert frame2 == expected


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
    dut.auth.value = 0
    await await_tx_valid(dut, "AUTH")
    assert dut.state.value in (1, 2), "Expected the fsm to be in running state"
    assert dut.active_transmission.value == AUTH, (
        "Expected active transmission to be of type auth"
    )
    frame = int(dut.mfrc_tx_data.value) >> 88
    assert frame == expected, f"Expected the value to be {bin(expected)}"
    assert int(dut.mfrc_tx_valid.value) == 1
    assert dut.authed.value == 0, "Expected authed to be low"

    response = int.from_bytes(secrets.token_bytes(16))
    await send_rx_response(dut, response)
    await RisingEdge(dut.clk)
    assert dut.state.value == 0, (
        "Expected the fsm to be in ready state - as the command was completed by response from card"
    )
    assert dut.authed.value == 1, "Expected authed to be high"


@cocotb.test()
async def test_get_id_transmission(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.get_id.value = 1
    await RisingEdge(dut.clk)
    dut.get_id.value = 0

    await await_tx_valid(dut, "GET_ID")
    assert dut.state.value in (1, 2), "Expected the fsm to be in running state"
    assert dut.active_transmission.value == GET_ID, (
        "Expected active transmission to be of type get_id"
    )
    frame = int(dut.mfrc_tx_data.value) >> 88
    cla = (frame >> 160) & 0xFF
    ins = (frame >> 152) & 0xFF
    assert cla == 0x80
    assert ins == 0x12
    assert int(dut.mfrc_tx_valid.value) == 1
    assert dut.id_retrieved.value == 0, "Expected that the id is not retrieved yet"

    response = int.from_bytes(secrets.token_bytes(16))
    await send_rx_response(dut, response)
    await RisingEdge(dut.clk)
    assert dut.state.value == 0, (
        "Expected the fsm to be in ready state - as the command was completed by response from card"
    )
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
    dut.get_id.value = 0
    await await_tx_valid(dut, "GET_ID")
    assert dut.state.value in (1, 2), "Expected the fsm to be in running state"
    await reset(dut)
    assert dut.state.value == 0, "Expected to be in ready state"
    assert dut.prog_selected.value == 0, "Expected that the id not to be retireved"
    assert int(dut.mfrc_tx_valid.value) == 0, "Expected tx_valid to be low"
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
