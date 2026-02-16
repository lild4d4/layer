"""
test_mfrc_core.py
Tests for mfrc_core transceive primitive, with the Mfrc522SpiSlave mock
attached to the SPI bus via cocotbext-spi.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import os
from cocotb_tools.runner import get_runner
from pathlib import Path

from cocotbext.spi import SpiBus
from mock_mfrc522 import Mfrc522SpiSlave


def _bytes_to_int(byte_list: list[int]) -> int:
    """Pack a list of bytes into a 256-bit integer (byte 0 = MSB)."""
    assert len(byte_list) <= 32, f"max 32 bytes (256 bits), got {len(byte_list)}"
    val = 0
    for b in byte_list:
        val = (val << 8) | b
    val <<= (32 - len(byte_list)) * 8
    return val


def _int_to_bytes(val: int, count: int) -> list[int]:
    """Extract count bytes from a 256-bit integer (byte 0 = MSB)."""
    assert count <= 32, f"max 32 bytes (256 bits), got {count}"
    result = []
    for i in range(count):
        shift = 255 - i * 8
        result.append((val >> (shift - 7)) & 0xFF)
    return result


# ─────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────


async def _reset(dut):
    """Apply active-high reset and initialise all inputs."""
    dut.rst.value = 1
    dut.trx_valid.value = 0
    dut.trx_tx_len.value = 0
    dut.trx_tx_data.value = 0
    dut.trx_tx_last_bits.value = 0
    dut.trx_timeout_cycles.value = 0
    dut.miso.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 5)


def _attach_mock(dut):
    """Attach the MFRC522 mock to cs0."""
    spi_bus = SpiBus.from_entity(dut, cs_name="cs0")
    return Mfrc522SpiSlave(spi_bus)


async def _do_transceive(
    dut, tx_bytes: list[int], tx_last_bits: int = 0, timeout_cycles: int = 500_000
) -> dict:
    """
    Drive the trx_valid handshake and wait for trx_done.
    len encoding: 0 = 1 byte, so len = len(tx_bytes) - 1.

    NOTE: timeout_cycles is the value passed to mfrc_core, which counts
    SPI poll round-trips (not raw clock cycles).  Each poll takes ~50
    clock cycles through spi_ctrl, so the Python wait budget must be
    scaled accordingly.
    """
    for _ in range(10):
        if dut.trx_ready.value == 1:
            break
        await RisingEdge(dut.clk)
    assert dut.trx_ready.value == 1, "mfrc_core not ready"

    dut.trx_tx_len.value = len(tx_bytes) - 1  # 0 = 1 byte
    dut.trx_tx_data.value = _bytes_to_int(tx_bytes)
    dut.trx_tx_last_bits.value = tx_last_bits
    dut.trx_timeout_cycles.value = timeout_cycles
    dut.trx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.trx_valid.value = 0

    # Each SPI poll round-trip costs ~50 clk.  Add margin for the
    # non-poll register accesses (flush, FIFO write, etc.) plus safety.
    clk_budget = timeout_cycles * 60 + 200_000

    for _ in range(clk_budget):
        await RisingEdge(dut.clk)
        if dut.trx_done.value == 1:
            break
    else:
        assert False, "Timed out waiting for trx_done"

    rx_len_enc = int(dut.trx_rx_len.value)  # 0 = 1 byte
    rx_count = rx_len_enc + 1
    rx_data_int = int(dut.trx_rx_data.value)
    rx_bytes = _int_to_bytes(rx_data_int, rx_count)

    return {
        "ok": bool(dut.trx_ok.value),
        "rx_len": rx_count,
        "rx_data": rx_bytes,
        "rx_last_bits": int(dut.trx_rx_last_bits.value),
        "error": int(dut.trx_error.value),
    }


# ─────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────


@cocotb.test()
async def test_transceive_reqa(dut):
    """Send REQA (0x26) with TxLastBits=7 → ATQA [0x04, 0x00]."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    result = await _do_transceive(dut, tx_bytes=[0x26], tx_last_bits=7)

    dut._log.info(f"REQA result: {result}")
    assert result["ok"], f"transceive failed: error={result['error']:#04x}"
    assert result["rx_len"] == 2
    assert result["rx_data"] == [0x04, 0x00]
    dut._log.info("test_transceive_reqa PASSED ✓")


@cocotb.test()
async def test_transceive_wupa(dut):
    """Send WUPA (0x52) with TxLastBits=7 → ATQA [0x04, 0x00]."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    result = await _do_transceive(dut, tx_bytes=[0x52], tx_last_bits=7)

    dut._log.info(f"WUPA result: {result}")
    assert result["ok"]
    assert result["rx_len"] == 2
    assert result["rx_data"] == [0x04, 0x00]
    dut._log.info("test_transceive_wupa PASSED ✓")


@cocotb.test()
async def test_transceive_anticoll(dut):
    """Send ANTICOLL CL1 (0x93 0x20) → UID + BCC (5 bytes)."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    uid = (0xDE, 0xAD, 0xBE, 0xEF)
    mock = _attach_mock(dut)

    result = await _do_transceive(dut, tx_bytes=[0x93, 0x20])

    bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
    expected = list(uid) + [bcc]

    dut._log.info(f"ANTICOLL result: {result}")
    assert result["ok"]
    assert result["rx_len"] == 5
    assert result["rx_data"] == expected
    dut._log.info("test_transceive_anticoll PASSED ✓")


@cocotb.test()
async def test_transceive_timeout(dut):
    """Send unknown command (0xFF) → mock produces no RxIRq → timeout."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    # 100 poll round-trips is enough to prove the timeout path;
    # keeping it small avoids a multi-second simulation.
    result = await _do_transceive(dut, tx_bytes=[0xFF], timeout_cycles=100)

    dut._log.info(f"Timeout result: {result}")
    assert not result["ok"], "Expected transceive to fail on timeout"
    dut._log.info("test_transceive_timeout PASSED ✓")


@cocotb.test()
async def test_trx_ready_deasserts(dut):
    """trx_ready goes low during a transceive, high again after."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    assert dut.trx_ready.value == 1

    dut.trx_tx_len.value = 0  # 0 = 1 byte
    dut.trx_tx_data.value = _bytes_to_int([0x26])
    dut.trx_tx_last_bits.value = 7
    dut.trx_timeout_cycles.value = 500_000
    dut.trx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.trx_valid.value = 0
    await RisingEdge(dut.clk)

    assert dut.trx_ready.value == 0, "trx_ready should be low during transaction"

    for _ in range(600_000):
        await RisingEdge(dut.clk)
        if dut.trx_done.value == 1:
            break

    await RisingEdge(dut.clk)
    assert dut.trx_ready.value == 1, "trx_ready should be high after completion"
    dut._log.info("test_trx_ready_deasserts PASSED ✓")


@cocotb.test()
async def test_back_to_back_transceive(dut):
    """REQA then ANTICOLL back-to-back — verifies core returns to idle between ops."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    result1 = await _do_transceive(dut, tx_bytes=[0x26], tx_last_bits=7)
    assert result1["ok"]
    assert result1["rx_data"] == [0x04, 0x00]

    uid = (0xDE, 0xAD, 0xBE, 0xEF)
    result2 = await _do_transceive(dut, tx_bytes=[0x93, 0x20])
    bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
    expected = list(uid) + [bcc]
    assert result2["ok"]
    assert result2["rx_data"] == expected
    dut._log.info("test_back_to_back_transceive PASSED ✓")


@cocotb.test()
async def test_error_reg_zero_on_success(dut):
    """On success, ErrorReg should be 0x00."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    result = await _do_transceive(dut, tx_bytes=[0x26], tx_last_bits=7)
    assert result["ok"]
    assert result["error"] == 0x00
    dut._log.info("test_error_reg_zero_on_success PASSED ✓")


@cocotb.test()
async def test_transceive_select_sak(dut):
    """SELECT CL1 (0x93 0x70 + UID + BCC) → SAK + CRC_A (3 bytes)."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    uid = [0xDE, 0xAD, 0xBE, 0xEF]
    bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
    select_cmd = [0x93, 0x70] + uid + [bcc]

    result = await _do_transceive(dut, tx_bytes=select_cmd)

    dut._log.info(f"SELECT result: {result}")
    assert result["ok"], f"transceive failed: error={result['error']:#04x}"
    # Real ISO14443-A SELECT response is SAK (1 byte) + CRC_A (2 bytes)
    assert result["rx_len"] == 3
    assert result["rx_data"][0] == 0x08

    def _crc_a(data: bytes) -> int:
        # ISO14443A CRC_A with preset 0x6363, poly 0x8408 (LSB-first)
        crc = 0x6363
        for b in data:
            crc ^= b
            for _ in range(8):
                if crc & 0x0001:
                    crc = (crc >> 1) ^ 0x8408
                else:
                    crc >>= 1
        return crc & 0xFFFF

    crc = _crc_a(bytes([0x08]))
    expected_crc = [crc & 0xFF, (crc >> 8) & 0xFF]
    assert result["rx_data"][1:] == expected_crc, (
        f"Expected CRC {expected_crc}, got {result['rx_data'][1:]}"
    )
    dut._log.info("test_transceive_select_sak PASSED ✓")


@cocotb.test()
async def test_transceive_error_injection(dut):
    """Inject a collision error (ErrorReg bit5) → trx_ok=0, trx_error≠0."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    # Inject CollErr (bit5 = 0x20) for the next transceive
    mock._inject_error = 0x20

    result = await _do_transceive(dut, tx_bytes=[0x93, 0x20])

    dut._log.info(f"Error injection result: {result}")
    assert not result["ok"], "Expected trx_ok=0 when ErrorReg is non-zero"
    assert result["error"] & 0x20, (
        f"Expected CollErr bit set, got {result['error']:#04x}"
    )
    dut._log.info("test_transceive_error_injection PASSED ✓")

    # Clean up for subsequent tests
    mock._inject_error = 0x00


@cocotb.test()
async def test_trx_valid_while_busy(dut):
    """Asserting trx_valid while a transceive is in progress should be ignored."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    # Start a normal REQA transaction
    dut.trx_tx_len.value = 0
    dut.trx_tx_data.value = _bytes_to_int([0x26])
    dut.trx_tx_last_bits.value = 7
    dut.trx_timeout_cycles.value = 500_000
    dut.trx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.trx_valid.value = 0
    await RisingEdge(dut.clk)

    assert dut.trx_ready.value == 0, "trx_ready should be low during transaction"

    # While busy, try to inject a different command (0xFF = unknown → timeout).
    # This should be silently ignored.
    await ClockCycles(dut.clk, 20)
    assert dut.trx_ready.value == 0
    dut.trx_tx_len.value = 0
    dut.trx_tx_data.value = _bytes_to_int([0xFF])
    dut.trx_tx_last_bits.value = 0
    dut.trx_timeout_cycles.value = 100
    dut.trx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.trx_valid.value = 0

    # Wait for completion — the original REQA should finish normally
    for _ in range(600_000):
        await RisingEdge(dut.clk)
        if dut.trx_done.value == 1:
            break

    rx_len_enc = int(dut.trx_rx_len.value)
    rx_count = rx_len_enc + 1
    rx_data_int = int(dut.trx_rx_data.value)
    rx_bytes = _int_to_bytes(rx_data_int, rx_count) if rx_data_int != 0 else []

    assert bool(dut.trx_ok.value), (
        "Original REQA should succeed despite spurious trx_valid"
    )
    assert rx_bytes == [0x04, 0x00], f"Expected ATQA, got {rx_bytes}"
    dut._log.info("test_trx_valid_while_busy PASSED ✓")


@cocotb.test()
async def test_transceive_immediate_timeout(dut):
    """timeout_cycles=0 → should timeout on the very first poll."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    # 0xFF is unknown to the mock, so no RxIRq.
    # With timeout_cycles=0, the first poll should trigger timeout.
    result = await _do_transceive(dut, tx_bytes=[0xFF], timeout_cycles=0)

    dut._log.info(f"Immediate timeout result: {result}")
    assert not result["ok"], "Expected transceive to fail immediately"
    dut._log.info("test_transceive_immediate_timeout PASSED ✓")


@cocotb.test()
async def test_transceive_full_bytes_tx_last_bits_zero(dut):
    """Explicit test that tx_last_bits=0 works and BitFramingReg is 0x00/0x80."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    # ANTICOLL with tx_last_bits=0 (full bytes)
    result = await _do_transceive(dut, tx_bytes=[0x93, 0x20], tx_last_bits=0)

    dut._log.info(f"Full-byte TX result: {result}")
    assert result["ok"]
    assert result["rx_last_bits"] == 0, "RxLastBits should be 0 for full-byte response"

    uid = [0xDE, 0xAD, 0xBE, 0xEF]
    bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
    assert result["rx_data"] == uid + [bcc]
    dut._log.info("test_transceive_full_bytes_tx_last_bits_zero PASSED ✓")


@cocotb.test()
async def test_transceive_max_burst_32_bytes(dut):
    """Send 31 TX bytes (max write burst — mfrc_reg_if uses 1 byte for
    the SPI address, leaving 31 of 32 bus bytes for payload).
    Unknown to the mock → exercises burst boundary via timeout path."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)
    mock = _attach_mock(dut)

    tx = list(range(31))
    result = await _do_transceive(dut, tx_bytes=tx, timeout_cycles=100)

    dut._log.info(f"Max burst result: {result}")
    # No PICC response for this payload, so we expect timeout
    assert not result["ok"], "Expected timeout for unknown 31-byte payload"
    dut._log.info("test_transceive_max_burst_32_bytes PASSED ✓")


# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────


def test_mfrc_core_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI

    src = proj_dir / "src"

    sources = [
        src / "spi_master.sv",
        src / "spi_ctrl.sv",
        src / "mfrc_top.sv",
        src / "mfrc_util.sv",
        src / "mfrc_reg_arb.sv",
        src / "mfrc_reg_if.sv",
        src / "mfrc_core.sv",
        test_dir / "test_mfrc_core_arb_top.sv",
    ]

    extra_paths = [str(test_dir)]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        extra_paths.append(existing)
    os.environ["PYTHONPATH"] = os.pathsep.join(extra_paths)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_mfrc_core_arb_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_mfrc_core_arb_top",
        test_module="test_mfrc_core_arb",
        waves=True,
    )


if __name__ == "__main__":
    test_mfrc_core_runner()
