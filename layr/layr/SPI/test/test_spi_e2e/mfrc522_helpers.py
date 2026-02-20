from pathlib import Path
from typing import Optional
from cocotb.triggers import RisingEdge
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


async def mfrc_wait_for_card_present(dut, timeout_us: int = 100_000) -> bool:
    """
    Wait for card_present to go high.
    Returns True if init completed, False on timeout.
    """
    for _ in range(timeout_us):
        await RisingEdge(dut.clk)
        if dut.mfrc_card_present.value == 1:
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
    dut,
    tx_bytes: list[int],
    tx_last_bits: int = 0,
    timeout_cycles: int = 5000,
    tx_kind: int = 0,
) -> dict:
    """
    Execute transceive command.

    Returns dict with:
        ok: bool - True if transaction succeeded
        rx_len: int - Number of bytes received
        rx_data: list[int] - Received bytes
        rx_last_bits: int - Valid bits in last byte (0 = all 8 valid)
        timeout: bool - True if no response (TimerIRq)
    """
    # Wait for TX ready
    for _ in range(100):
        if dut.mfrc_tx_ready.value == 1:
            break
        await RisingEdge(dut.clk)
    else:
        raise Exception("Timed out waiting for mfrc_tx_ready")

    # Set TX data
    dut.mfrc_tx_len.value = len(tx_bytes) - 1
    dut.mfrc_tx_data.value = _bytes_to_int(tx_bytes)
    dut.mfrc_tx_last_bits.value = tx_last_bits
    dut.mfrc_tx_kind.value = tx_kind
    dut.mfrc_tx_valid.value = 1

    await RisingEdge(dut.clk)
    dut.mfrc_tx_valid.value = 0

    # Wait for response
    clk_budget = timeout_cycles * 60 + 10_000
    for _ in range(clk_budget):
        await RisingEdge(dut.clk)
        if dut.mfrc_rx_valid.value == 1:
            break
    else:
        return {
            "ok": False,
            "rx_len": 0,
            "rx_data": [],
            "rx_last_bits": 0,
            "timeout": True,
        }

    # Parse response
    rx_len_enc = int(dut.mfrc_rx_len.value)
    rx_count = rx_len_enc + 1
    rx_data_int = int(dut.mfrc_rx_data.value)
    rx_bytes = _int_to_bytes(rx_data_int, rx_count)

    # Check for timeout flag if available
    timeout = False
    if hasattr(dut, "mfrc_rx_timeout"):
        timeout = bool(dut.mfrc_rx_timeout.value)

    return {
        "ok": bool(dut.mfrc_rx_valid.value) and not timeout,
        "rx_len": rx_count,
        "rx_data": rx_bytes,
        "rx_last_bits": int(dut.mfrc_rx_last_bits.value),
        "timeout": timeout,
    }


async def mfrc_reqa(dut) -> int | None:
    """
    Send REQA (0x26) command.

    Returns:
        ATQA as 16-bit int (e.g., 0x0400) on success
        None on timeout/error
    """
    result = await mfrc_transceive(dut, tx_bytes=[0x26], tx_last_bits=7)

    print(result)

    if not result["ok"] or result["rx_len"] < 2:
        return None

    # ATQA is 2 bytes, LSB first from card but we receive MSB first in our buffer
    # Depends on your byte ordering - adjust if needed
    atqa = (result["rx_data"][0] << 8) | result["rx_data"][1]
    return atqa


async def mfrc_wupa(dut) -> int | None:
    """
    Send WUPA (0x52) command to wake up all cards.

    Returns:
        ATQA as 16-bit int on success
        None on timeout/error
    """
    result = await mfrc_transceive(dut, tx_bytes=[0x52], tx_last_bits=7)
    dut._log.info(f"WUPA Reponse: {result}")

    if not result["ok"] or result["rx_len"] < 2:
        return None

    atqa = (result["rx_data"][0] << 8) | result["rx_data"][1]
    return atqa


async def mfrc_anticoll(dut) -> bytes | None:
    """
    Send ANTICOLLISION CL1 (0x93 0x20) command.

    Returns:
        5 bytes (UID[4] + BCC) as bytes object on success
        None on timeout/error
    """
    result = await mfrc_transceive(dut, tx_bytes=[0x93, 0x20])

    if not result["ok"] or result["rx_len"] < 5:
        return None

    # Return UID (4 bytes) + BCC (1 byte)
    return bytes(result["rx_data"][:5])


async def mfrc_select(
    dut, uid: Optional[bytes] = None, bcc: Optional[int] = None
) -> Optional[int]:
    """
    Send SELECT CL1 command with UID.

    Args:
        dut: Device under test
        mfrc: MFRC522 mock (unused, for API compatibility)
        uid: 4-byte UID as bytes
        bcc: BCC byte (optional, calculated if not provided)

    Returns:
        SAK byte on success
        None on timeout/error
    """
    if uid is None:
        return None

    # Ensure uid is a list of ints
    if isinstance(uid, bytes):
        uid_list = list(uid)

    # Calculate BCC if not provided
    if bcc is None:
        bcc = uid_list[0] ^ uid_list[1] ^ uid_list[2] ^ uid_list[3]

    # SELECT CL1: 0x93 0x70 + UID[4] + BCC
    # Note: Real implementation would also append CRC_A, but mfrc_core handles that
    select_cmd = [0x93, 0x70] + uid_list[:4] + [bcc]

    result = await mfrc_transceive(dut, tx_bytes=select_cmd)

    if not result["ok"] or result["rx_len"] < 1:
        return None

    # SAK is first byte of response (followed by CRC_A which we ignore)
    sak = result["rx_data"][0]
    return sak


async def mfrc_rats(dut) -> bytes | None:
    """
    Send RATS (0xE0 0x50) as a dedicated RATS transaction kind.

    Returns ATS bytes on success, None on timeout/error.
    """
    result = await mfrc_transceive(dut, tx_bytes=[0xE0, 0x50], tx_kind=1)

    if not result["ok"] or result["rx_len"] < 1:
        return None

    return bytes(result["rx_data"])


async def mfrc_transceive_raw(
    dut,
    tx_bytes: list[int],
    tx_last_bits: int = 0,
    timeout_cycles: int = 5000,
    tx_kind: int = 0,
) -> dict:
    """
    Raw transceive - returns full result dict for debugging.
    Same as mfrc_transceive but explicitly named for clarity.
    """
    return await mfrc_transceive(dut, tx_bytes, tx_last_bits, timeout_cycles, tx_kind)
