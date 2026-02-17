from pathlib import Path
from cocotb.triggers import RisingEdge, Timer
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from test_mfrc522.mock_mfrc522 import Mfrc522SpiSlave
from helpers import build_spi_bus


async def mfrc_setup(dut):
    """Attach MFRC522 mock to cs_0 (MFRC522 chip select)."""
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


async def mfrc_wait_for_init(dut, timeout_us: int = 100000) -> bool:
    """
    Wait for init_done to go high.
    Returns True if init completed, False on timeout.
    """
    for _ in range(timeout_us):
        await RisingEdge(dut.clk)
        if dut.mfrc_init_done.value == 1:
            return True
    return False


async def mfrc_wait_for_card(dut, timeout_us: int = 100000) -> bool:
    """
    Wait for card_present to go high.
    Returns True if card detected, False on timeout.
    """
    for _ in range(timeout_us):
        await RisingEdge(dut.clk)
        if dut.mfrc_card_present.value == 1:
            return True
    return False


async def mfrc_transceive(
    dut, tx_bytes: list[int], tx_last_bits: int = 0, timeout_cycles: int = 5000
) -> dict:
    """Execute transceive, return {ok, rx_len, rx_data, rx_last_bits, error}."""
    for _ in range(10):
        if dut.mfrc_tx_ready.value == 1:
            break
        await RisingEdge(dut.clk)

    dut.mfrc_tx_len.value = len(tx_bytes) - 1
    dut.mfrc_tx_data.value = _bytes_to_int(tx_bytes)
    dut.mfrc_tx_last_bits.value = tx_last_bits
    dut.mfrc_tx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.mfrc_tx_valid.value = 0

    clk_budget = timeout_cycles * 60 + 10_000
    for _ in range(clk_budget):
        await RisingEdge(dut.clk)
        if dut.mfrc_rx_valid.value == 1:
            break
    else:
        raise Exception("Timed out waiting for mfrc_rx_valid")

    rx_len_enc = int(dut.mfrc_rx_len.value)
    rx_count = rx_len_enc + 1
    rx_data_int = int(dut.mfrc_rx_data.value)
    rx_bytes = _int_to_bytes(rx_data_int, rx_count)

    return {
        "ok": bool(dut.mfrc_rx_ok.value),
        "rx_len": rx_count,
        "rx_data": rx_bytes,
        "rx_last_bits": int(dut.mfrc_rx_last_bits.value),
        "error": int(dut.mfrc_rx_error.value),
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
