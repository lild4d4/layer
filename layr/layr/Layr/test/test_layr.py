"""
Modern cocotb 2.0 testbench for the Controller module.
Uses async/await syntax and modern pythonic patterns.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, with_timeout

from cocotb_tools.runner import get_runner
from Crypto.Cipher import AES

os.environ["COCOTB_ANSI_OUTPUT"] = "1"


class LayrTester:
    """Helper class for Controller module testing."""

    def __init__(self, dut):
        self.dut = dut


async def reset(dut):
    """Apply reset pulse."""
    dut.card_present_i.value = 0

    # MFRC streaming interface inputs
    dut.mfrc_tx_ready.value = 1
    dut.mfrc_rx_valid.value = 0
    dut.mfrc_rx_len.value = 0
    dut.mfrc_rx_data.value = 0
    dut.mfrc_rx_last_bits.value = 0

    dut.eeprom_busy.value = 0
    dut.eeprom_done.value = 0
    dut.eeprom_buffer.value = 0

    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_happy_path(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
    card_id = bytes.fromhex("d0d23f18251c6087566de7b7deab7774")
    result = await run_validation(
        dut, key=key, card_id=card_id, expected_id=card_id, rst=True
    )
    assert result == 1, "Expected the id to be valid"


@cocotb.test()
async def test_happy_invalid(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
    card_id = bytes.fromhex("d0d23f18251c6087566de7b7deab7774")
    expected_id = card_id[:-1] + b"\xff"
    result = await run_validation(
        dut, key=key, card_id=card_id, expected_id=expected_id, rst=True
    )
    assert result == 0, "Expected the id to be invalid"


def _u128_from_bytes(data: bytes) -> int:
    return int.from_bytes(data, byteorder="big", signed=False)


async def _eeprom_model(dut, *, key: bytes, expected_id: bytes):
    """Simple EEPROM responder used by the real `auth` RTL.

    - When `eeprom_get_key==1`, returns `key`.
    - Otherwise, returns `expected_id`.
    """

    in_flight = False
    while True:
        await RisingEdge(dut.clk)

        if int(dut.rst.value):
            dut.eeprom_done.value = 0
            dut.eeprom_buffer.value = 0
            in_flight = False
            continue

        if int(dut.eeprom_start.value) and not in_flight:
            in_flight = True
            payload = key if int(dut.eeprom_get_key.value) else expected_id
            dut.eeprom_buffer.value = _u128_from_bytes(payload)
            dut.eeprom_done.value = 1
            await RisingEdge(dut.clk)
            dut.eeprom_done.value = 0
            dut.eeprom_buffer.value = 0

        if in_flight and not int(dut.eeprom_start.value):
            in_flight = False


async def run_validation(dut, *, key: bytes, card_id: bytes, expected_id: bytes, rst):
    # Start EEPROM model for this session
    eeprom_task = cocotb.start_soon(
        _eeprom_model(dut, key=key, expected_id=expected_id)
    )

    if rst:
        await reset(dut)
    assert int(dut.mfrc_tx_valid.value) == 0
    dut.card_present_i.value = 1

    await RisingEdge(dut.clk)
    dut.card_present_i.value = 0

    await await_tx_valid(dut, "ANTICOLL Command")
    assert int(dut.mfrc_tx_len.value) == 1
    anti_coll_frame = int(dut.mfrc_tx_data.value) >> (256 - 2 * 8)
    assert anti_coll_frame == 0x9320
    assert dut.busy.value == 1, "Expected the layer controller to be busy"

    uid = [0xDE, 0xAD, 0xBE, 0xEF]
    bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
    await send_rx_bytes(dut, uid + [bcc])

    await await_tx_valid(dut, "SELECT CARD Command")
    assert int(dut.mfrc_tx_len.value) == 8  # 9 bytes
    select_card_frame = int(dut.mfrc_tx_data.value) >> (256 - 9 * 8)
    assert (select_card_frame >> 56) & 0xFFFF == 0x9370
    assert (select_card_frame >> 16) & 0xFFFFFFFFFF == int.from_bytes(
        bytes(uid + [bcc]), byteorder="big"
    )

    await send_rx_bytes(dut, [0x08, 0x00, 0x00])

    await await_tx_valid(dut, "RATS Command")
    assert int(dut.mfrc_tx_len.value) == 1  # 2 bytes
    rats_frame = int(dut.mfrc_tx_data.value) >> (256 - 2 * 8)
    assert rats_frame == 0xE050
    assert int(dut.mfrc_tx_kind.value) == 1

    await send_rx_bytes(dut, [0x05, 0x78, 0x80, 0x70, 0x00])

    await await_tx_valid(dut, "Select Prog Command")
    assert int(dut.mfrc_tx_len.value) == 11  # 12 bytes (I-Block + 11-byte APDU)
    select_frame = int(dut.mfrc_tx_data.value) >> (256 - 12 * 8)
    assert select_frame == 0x0200A4040006F000000CDC00, (
        "Expected chip select command in I-Block"
    )

    await send_rx_bytes(dut, [0x02, 0x90, 0x00])

    assert int(dut.mfrc_tx_valid.value) == 0
    await await_tx_valid(dut, "Auth_Init Command")
    assert int(dut.mfrc_tx_len.value) == 21  # 22 bytes (I-Block + 21-byte APDU)
    auth_init_frame = int(dut.mfrc_tx_data.value) >> 80
    pcb = (auth_init_frame >> 168) & 0xFF
    cla = (auth_init_frame >> 160) & 0xFF
    ins = (auth_init_frame >> 152) & 0xFF
    assert pcb == 0x03
    assert cla == 0x80
    assert ins == 0x10

    # Card returns encrypted challenge seed (ciphertext). Auth RTL will decrypt and
    # use the upper 64b as rc.
    rc = bytes.fromhex("1111cafEaffe1111")
    plain = rc + (b"\x00" * 8)
    card_cipher = AES.new(key, AES.MODE_ECB).encrypt(plain)
    await send_rx_bytes(dut, [0x02] + list(card_cipher))

    assert dut.chip_cypher.value == 0, "Expected the challenge not to be set yet"
    assert int(dut.mfrc_tx_valid.value) == 0

    # Wait for challenge to be generated by the (cycle-heavy) AES auth pipeline and
    # latched into `chip_cypher` by the top-level.
    await with_timeout(
        _await_nonzero(dut.auth_i.chip_challenge_generated, dut.clk),
        timeout_time=50_000,
        timeout_unit="ns",
    )
    await with_timeout(
        _await_nonzero(dut.chip_cypher, dut.clk), timeout_time=5_000, timeout_unit="ns"
    )

    await await_tx_valid(dut, "Auth Command")
    cmd = int(dut.mfrc_tx_data.value) >> 80
    pcb = (cmd >> 168) & 0xFF
    cla = (cmd >> 160) & 0xFF
    ins = (cmd >> 152) & 0xFF
    payload = cmd & ((1 << 128) - 1)

    assert pcb == 0x02
    assert cla == 0x80, f"Expected CLA=0x80, got {cla:#x}"
    assert ins == 0x11, f"Expected INS=0x11, got {ins:#x}"
    assert payload == int(dut.chip_cypher.value), "AUTH payload != chip_cypher"

    await send_rx_bytes(dut, [0x03, 0x90, 0x00])

    assert int(dut.mfrc_tx_valid.value) == 0

    await await_tx_valid(dut, "Get Id")
    get_id_frame = int(dut.mfrc_tx_data.value) >> 80
    pcb = (get_id_frame >> 168) & 0xFF
    cla = (get_id_frame >> 160) & 0xFF
    ins = (get_id_frame >> 152) & 0xFF
    assert pcb == 0x03
    assert cla == 0x80
    assert ins == 0x12

    # Card returns encrypted ID using the session key produced during challenge generation.
    session_key = int(dut.auth_i.auth_i.session_key.value).to_bytes(
        16, byteorder="big", signed=False
    )
    id_cipher = AES.new(session_key, AES.MODE_ECB).encrypt(card_id)
    await send_rx_bytes(dut, [0x02] + list(id_cipher))

    await await_status_valid(dut)
    result = dut.status.value
    await advance_cycles(dut, 1)
    assert dut.busy.value == 0, "Expected the layer controller not to be busy anymore"

    eeprom_task.cancel()
    return result


async def send_rx_bytes(dut, values: list[int]):
    value = 0
    for b in values:
        value = (value << 8) | (b & 0xFF)
    dut.mfrc_rx_data.value = value << (256 - len(values) * 8)
    dut.mfrc_rx_len.value = len(values) - 1
    dut.mfrc_rx_last_bits.value = 0
    dut.mfrc_rx_valid.value = 1
    # Hold long enough for the DUT to advance SEND -> WAIT_RX and sample rx_valid.
    await ClockCycles(dut.clk, 2)
    dut.mfrc_rx_valid.value = 0
    dut.mfrc_rx_data.value = 0
    dut.mfrc_rx_len.value = 0


async def await_tx_valid(dut, msg):
    for _ in range(1000):
        await RisingEdge(dut.clk)
        if int(dut.mfrc_tx_valid.value):
            break
    assert int(dut.mfrc_tx_valid.value) == 1, (
        f"{msg}: did not become valid within the maximum number of time steps"
    )


async def await_status_valid(dut):
    for _ in range(1000):
        await RisingEdge(dut.clk)
        if dut.status_valid.value:
            break
    assert dut.status_valid.value == 1, (
        "did not validate in maximum number of time steps"
    )


async def await_validated(dut, msg):
    for _ in range(1000):
        await RisingEdge(dut.clk)
        if int(dut.mfrc_tx_valid.value):
            break
    assert int(dut.mfrc_tx_valid.value) == 1, (
        f"{msg}: did not become valid within the maximum number of time steps"
    )


async def advance_cycles(dut, cycles: int):
    """Helper to advance a given number of clock cycles."""
    await ClockCycles(dut.clk, cycles)


async def _await_nonzero(signal, clk):
    while int(signal.value) == 0:
        await RisingEdge(clk)


@cocotb.test()
async def test_no_command_without_card_present_i(dut):
    """Ensure no command is issued when no card is present."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Keep card absent and let the design run for a few cycles
    dut.card_present_i.value = 0
    dut.mfrc_rx_valid.value = 0
    await advance_cycles(dut, 5)

    # With no card present, we don't expect a TX request to be driven
    assert int(dut.mfrc_tx_valid.value) == 0, "Expected no TX when card is not present"


@cocotb.test()
async def test_multiple_happy_sessions(dut):
    """Run the happy path multiple times to check stability."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
    card_id = bytes.fromhex("d0d23f18251c6087566de7b7deab7774")

    for i in range(20):
        valid = (i // 5) % 2
        expected_id = card_id if valid else (card_id[:-1] + b"\xff")

        result = await run_validation(
            dut, key=key, card_id=card_id, expected_id=expected_id, rst=i == 0
        )
        assert int(result) == valid, f"Expected validation={valid} for session {i}"


def test_layr_controller_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    root = proj_path / "src"
    auth = proj_path.parent / "Auth"
    auth_sources = auth / "src"
    aes = auth / "secworks-aes" / "src" / "rtl"

    sources = [p for p in root.rglob("*") if p.is_file()]
    sources += [p for p in auth_sources.rglob("*") if p.is_file()]
    sources += [p for p in aes.rglob("*") if p.is_file()]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="layr",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        verbose=True,
    )

    runner.test(hdl_toplevel="layr", test_module="test_layr", waves=True)


if __name__ == "__main__":
    test_layr_controller_runner()
