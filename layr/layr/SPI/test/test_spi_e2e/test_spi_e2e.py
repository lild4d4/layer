import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, First
from cocotbext.spi import SpiBus

import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from test_at25010b.at25010b_mock import AT25010B_EEPROM
from test_mfrc522.mock_mfrc522 import Mfrc522SpiSlave

from cocotb_tools.runner import get_runner

CLK_PERIOD_NS = 10  # 100Mhz
RESET_CYCLES = 5
TRANSACTION_TIMEOUT_US = 500


def build_spi_bus(dut, cs: int) -> SpiBus:
    """
    Build a SpiBus from the tb_top SPI port using custom signal names.

    The SpiBus.from_entity() method automatically finds signals by name,
    so we tell it the actual signal names used in eeprom_wire_modules.sv.
    """

    return SpiBus.from_entity(
        dut,
        sclk_name="spi_sclk",
        mosi_name="spi_mosi",
        miso_name="spi_miso",
        cs_name=f"cs_{cs}",
    )


async def reset_dut(dut):
    """Assert reset for RESET_CYCLES, then release and wait for init."""
    dut.rst.value = 1

    dut.spi_miso.value = 1

    dut.eeprom_start.value = 0
    dut.eeprom_get_key.value = 0

    dut.mfrc_trx_valid.value = 0
    dut.mfrc_trx_tx_len.value = 0
    dut.mfrc_trx_tx_data.value = 0
    dut.mfrc_trx_tx_last_bits.value = 0
    dut.mfrc_trx_timeout_cycles.value = 0
    dut.mfrc_ver_valid.value = 0

    for _ in range(RESET_CYCLES):
        await RisingEdge(dut.clk)

    dut.rst.value = 0

    await RisingEdge(dut.clk)


async def wait_done(dut, wait_cond, timeout_us: int = TRANSACTION_TIMEOUT_US) -> None:
    """
    Block until wait_done pulses high, or raise TestFailure on timeout.
    """
    timeout_trigger = Timer(timeout_us, "us")
    done_trigger = RisingEdge(wait_cond)

    result = await First(done_trigger, timeout_trigger)
    if result is timeout_trigger:
        raise Exception(f"Timed out after {timeout_us} µs waiting for done. ")

    await RisingEdge(dut.clk)


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    eeprom = await eeprom_setup(dut)
    mfrc = await mfrc_setup(dut)

    await reset_dut(dut)

    return (eeprom, mfrc)


#
# EEPROM Stuff
#

KEY_A = bytes.fromhex("39558d1f193656ab8b4b65e25ac48474")
ID_A = bytes.fromhex("bbe8278a67f960605adafd6f63cf7ba7")


async def eeprom_setup(dut) -> AT25010B_EEPROM:
    """
    Start the simulation clock, reset the DUT, and attach the EEPROM mock.
    Returns the mock so tests can pre-load / inspect memory.
    """
    eeprom = AT25010B_EEPROM(build_spi_bus(dut, 1))

    eeprom.load_memory(KEY_A, offset=0x00)
    eeprom.load_memory(ID_A, offset=0x40)

    return eeprom


async def eeprom_send_cmd(dut, get_key: int) -> None:
    """
    Drive a one-cycle eeprom_start pulse to start a transaction.

    The caller must then wait for cmd_done (use wait_done()).
    """
    dut.eeprom_get_key.value = get_key
    dut.eeprom_start.value = 1
    await RisingEdge(dut.clk)
    dut.eeprom_start.value = 0

    await wait_done(dut, dut.eeprom_done)

    return dut.eeprom_rbuffer.value


#
# MFRC Stuff
#


async def mfrc_setup(dut):
    mfrc = Mfrc522SpiSlave(build_spi_bus(dut, 0))

    return mfrc


def _bytes_to_int(byte_list: list[int]) -> int:
    """Pack bytes into 256-bit integer (byte 0 = MSB)."""
    val = 0
    for b in byte_list:
        val = (val << 8) | b
    val <<= (32 - len(byte_list)) * 8
    return val


def _int_to_bytes(val: int, count: int) -> list[int]:
    """Extract count bytes from a 256-bit integer (byte 0 = MSB)."""
    result = []
    for i in range(count):
        shift = 255 - i * 8
        result.append((val >> (shift - 7)) & 0xFF)
    return result


async def mfrc_transceive(
    dut, tx_bytes: list[int], tx_last_bits: int = 0, timeout_cycles: int = 500_000
) -> dict:
    """Execute transceive, return {ok, rx_len, rx_data, rx_last_bits, error}."""
    for _ in range(10):
        if dut.mfrc_trx_ready.value == 1:
            break
        await RisingEdge(dut.clk)

    dut.mfrc_trx_tx_len.value = len(tx_bytes) - 1
    dut.mfrc_trx_tx_data.value = _bytes_to_int(tx_bytes)
    dut.mfrc_trx_tx_last_bits.value = tx_last_bits
    dut.mfrc_trx_timeout_cycles.value = timeout_cycles
    dut.mfrc_trx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.mfrc_trx_valid.value = 0

    clk_budget = timeout_cycles * 60 + 200_000
    for _ in range(clk_budget):
        await RisingEdge(dut.clk)
        if dut.mfrc_trx_done.value == 1:
            break
    else:
        raise Exception("Timed out waiting for mfrc_trx_done")

    rx_len_enc = int(dut.mfrc_trx_rx_len.value)
    rx_count = rx_len_enc + 1
    rx_data_int = int(dut.mfrc_trx_rx_data.value)
    rx_bytes = _int_to_bytes(rx_data_int, rx_count)

    return {
        "ok": bool(dut.mfrc_trx_ok.value),
        "rx_len": rx_count,
        "rx_data": rx_bytes,
        "rx_last_bits": int(dut.mfrc_trx_rx_last_bits.value),
        "error": int(dut.mfrc_trx_error.value),
    }


async def mfrc_reqa(dut) -> dict:
    """Send REQA (0x26), check for card. Returns transceive result."""
    return await mfrc_transceive(dut, tx_bytes=[0x26], tx_last_bits=7)


async def mfrc_wupa(dut) -> dict:
    """Send WUPA (0x52), wake up card. Returns transceive result."""
    return await mfrc_transceive(dut, tx_bytes=[0x52], tx_last_bits=7)


async def mfrc_anticoll(dut) -> dict:
    """Send ANTICOLL CL1 (0x93 0x20), get UID. Returns transceive result."""
    return await mfrc_transceive(dut, tx_bytes=[0x93, 0x20])


async def mfrc_select(dut, uid: list[int]) -> dict:
    """Send SELECT CL1 with UID, select card. Returns transceive result."""
    bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
    select_cmd = [0x93, 0x70] + uid + [bcc]
    return await mfrc_transceive(dut, tx_bytes=select_cmd)


#
# Tests
#


@cocotb.test()
async def test_reset_state(dut):
    """After reset, eeprom_busy must be low and eeprom_done must be low."""
    await setup(dut)
    await RisingEdge(dut.clk)

    assert int(dut.eeprom_busy.value) == 0, "busy should be 0 after reset"
    assert int(dut.eeprom_done.value) == 0, "done should be 0 after reset"


@cocotb.test()
async def test_eeprom_get_key(dut):
    """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
    _ = await setup(dut)

    result = await eeprom_send_cmd(dut, 1)
    expected = int.from_bytes(KEY_A, byteorder="big")
    assert result == expected, f"Expected {expected:#x}, got {result:#x}"


@cocotb.test()
async def test_eeprom_get_id(dut):
    """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
    _ = await setup(dut)

    result = await eeprom_send_cmd(dut, 0)
    expected = int.from_bytes(ID_A, byteorder="big")
    assert result == expected, f"Expected {expected:#x}, got {result:#x}"


#
# MFRC Tests
#


MOCK_UID = [0xDE, 0xAD, 0xBE, 0xEF]


@cocotb.test()
async def test_mfrc_reqa(dut):
    """Send REQA (0x26) → expect ATQA [0x04, 0x00]."""
    _ = await setup(dut)

    result = await mfrc_reqa(dut)

    assert result["ok"], f"REQA failed: error={result['error']:#04x}"
    assert result["rx_len"] == 2, f"Expected 2 bytes, got {result['rx_len']}"
    assert result["rx_data"] == [0x04, 0x00], f"Expected ATQA, got {result['rx_data']}"
    assert result["rx_last_bits"] == 0, "Expected full bytes in response"


@cocotb.test()
async def test_mfrc_wupa(dut):
    """Send WUPA (0x52) → expect ATQA [0x04, 0x00]."""
    _ = await setup(dut)

    result = await mfrc_wupa(dut)

    assert result["ok"], f"WUPA failed: error={result['error']:#04x}"
    assert result["rx_len"] == 2, f"Expected 2 bytes, got {result['rx_len']}"
    assert result["rx_data"] == [0x04, 0x00], f"Expected ATQA, got {result['rx_data']}"


@cocotb.test()
async def test_mfrc_anticoll(dut):
    """Send ANTICOLL CL1 (0x93 0x20) → expect UID + BCC (5 bytes)."""
    _ = await setup(dut)

    result = await mfrc_anticoll(dut)

    bcc = MOCK_UID[0] ^ MOCK_UID[1] ^ MOCK_UID[2] ^ MOCK_UID[3]
    expected = MOCK_UID + [bcc]

    assert result["ok"], f"ANTICOLL failed: error={result['error']:#04x}"
    assert result["rx_len"] == 5, f"Expected 5 bytes, got {result['rx_len']}"
    assert (
        result["rx_data"] == expected
    ), f"Expected UID {expected}, got {result['rx_data']}"


@cocotb.test()
async def test_mfrc_select(dut):
    """Send SELECT with UID → expect SAK + CRC_A (3 bytes)."""
    _ = await setup(dut)

    result = await mfrc_select(dut, MOCK_UID)

    assert result["ok"], f"SELECT failed: error={result['error']:#04x}"
    assert result["rx_len"] == 3, f"Expected 3 bytes, got {result['rx_len']}"
    assert (
        result["rx_data"][0] == 0x08
    ), f"Expected SAK=0x08, got {result['rx_data'][0]:#04x}"


@cocotb.test()
async def test_mfrc_card_activate_sequence(dut):
    """Full card activation: REQA → ANTICOLL → SELECT."""
    _ = await setup(dut)

    result = await mfrc_reqa(dut)
    assert result["ok"]
    assert result["rx_data"] == [0x04, 0x00]

    result = await mfrc_anticoll(dut)
    assert result["ok"]
    uid = result["rx_data"][:4]
    assert uid == MOCK_UID

    result = await mfrc_select(dut, uid)
    assert result["ok"]
    assert result["rx_data"][0] == 0x08


#
# Runner
#


def test_spi_e2e_runner():
    sim = os.getenv("SIM", "icarus")
    spi_module_path = Path(__file__).resolve().parent.parent.parent
    src_dir = spi_module_path / "src"

    exclude = ["mfrc_util.sv", "mfrc_core.sv"]
    sources = list(src_dir.glob("*.sv"))
    sources = [src for src in sources if src.name not in exclude]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="spi_top",
        test_module="test_spi_e2e",
        waves=True,
    )


if __name__ == "__main__":
    test_spi_e2e_runner()
