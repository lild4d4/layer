import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from at25010b_helpers import eeprom_setup, eeprom_send_cmd, KEY_A, ID_A
from mfrc522_helpers import (
    mfrc_setup,
    mfrc_reqa,
    mfrc_anticoll,
    mfrc_select,
    mfrc_wupa,
    mfrc_wait_for_init,
    mfrc_wait_for_card,
)
from helpers import reset_dut
from cocotb_tools.runner import get_runner
from cocotb.triggers import RisingEdge

CLK_PERIOD_NS = 10  # 100Mhz


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    eeprom = await eeprom_setup(dut)
    mfrc = await mfrc_setup(dut)

    await reset_dut(dut)

    return (eeprom, mfrc)


#
# AT25010B Tests
#


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


@cocotb.test()
async def test_eeprom_conseq(dut):
    """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
    _ = await setup(dut)

    result = await eeprom_send_cmd(dut, 0)
    expected = int.from_bytes(ID_A, byteorder="big")
    assert result == expected, f"1: Expected {expected:#x}, got {result:#x}"

    result = await eeprom_send_cmd(dut, 1)
    expected = int.from_bytes(KEY_A, byteorder="big")
    assert result == expected, f"2: Expected {expected:#x}, got {result:#x}"

    result = await eeprom_send_cmd(dut, 1)
    expected = int.from_bytes(KEY_A, byteorder="big")
    assert result == expected, f"3: Expected {expected:#x}, got {result:#x}"

    result = await eeprom_send_cmd(dut, 0)
    expected = int.from_bytes(ID_A, byteorder="big")
    assert result == expected, f"4: Expected {expected:#x}, got {result:#x}"


#
# MFRC Tests (with auto-init and card polling)
#


MOCK_UID = [0xDE, 0xAD, 0xBE, 0xEF]


@cocotb.test()
async def test_mfrc_auto_init(dut):
    """Verify that mfrc_init_done goes high after auto-initialization."""
    _ = await setup(dut)
    dut._log.info("Waiting for MFRC auto-initialization...")

    # Wait for init to complete
    init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
    assert init_ok, "MFRC auto-init did not complete in time"
    assert dut.mfrc_init_done.value == 1, "init_done should be 1"
    assert dut.mfrc_ready.value == 1, "ready should be 1 after init"

    dut._log.info(f"init_done={dut.mfrc_init_done.value}, ready={dut.mfrc_ready.value}")
    dut._log.info("test_mfrc_auto_init PASSED ✓")


#
# @cocotb.test()
# async def test_mfrc_auto_card_detection(dut):
#     """Verify that card_present goes high when card is detected via auto-poll."""
#     _ = await setup(dut)
#     dut._log.info("Waiting for MFRC auto-initialization and card detection...")
#
#     # Wait for card to be detected (auto-poll runs after init)
#     card_detected = await mfrc_wait_for_card(dut, timeout_us=300000)
#     assert card_detected, "Card was not detected in time"
#
#     assert dut.mfrc_card_present.value == 1, "card_present should be 1"
#     assert (
#         dut.mfrc_atqa.value == 0x0400
#     ), f"Expected ATQA=0x0400, got {dut.mfrc_atqa.value:#06x}"
#
#     dut._log.info(
#         f"card_present={dut.mfrc_card_present.value}, atqa={dut.mfrc_atqa.value:#06x}"
#     )
#     dut._log.info("test_mfrc_auto_card_detection PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_reqa_after_init(dut):
#     """Send REQA (0x26) → expect ATQA [0x04, 0x00] after init complete."""
#     _ = await setup(dut)
#
#     # Wait for init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     # Now send REQA
#     result = await mfrc_reqa(dut)
#
#     assert result["ok"], f"REQA failed: error={result['error']:#04x}"
#     assert result["rx_len"] == 2, f"Expected 2 bytes, got {result['rx_len']}"
#     assert result["rx_data"] == [0x04, 0x00], f"Expected ATQA, got {result['rx_data']}"
#     assert result["rx_last_bits"] == 0, "Expected full bytes in response"
#
#     dut._log.info("test_mfrc_reqa_after_init PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_wupa_after_init(dut):
#     """Send WUPA (0x52) → expect ATQA [0x04, 0x00] after init complete."""
#     _ = await setup(dut)
#
#     # Wait for init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     result = await mfrc_wupa(dut)
#
#     assert result["ok"], f"WUPA failed: error={result['error']:#04x}"
#     assert result["rx_len"] == 2, f"Expected 2 bytes, got {result['rx_len']}"
#     assert result["rx_data"] == [0x04, 0x00], f"Expected ATQA, got {result['rx_data']}"
#
#     dut._log.info("test_mfrc_wupa_after_init PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_anticoll_after_init(dut):
#     """Send ANTICOLL CL1 (0x93 0x20) → expect UID + BCC (5 bytes) after init."""
#     _ = await setup(dut)
#
#     # Wait for init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     result = await mfrc_anticoll(dut)
#
#     bcc = MOCK_UID[0] ^ MOCK_UID[1] ^ MOCK_UID[2] ^ MOCK_UID[3]
#     expected = MOCK_UID + [bcc]
#
#     assert result["ok"], f"ANTICOLL failed: error={result['error']:#04x}"
#     assert result["rx_len"] == 5, f"Expected 5 bytes, got {result['rx_len']}"
#     assert (
#         result["rx_data"] == expected
#     ), f"Expected UID {expected}, got {result['rx_data']}"
#
#     dut._log.info("test_mfrc_anticoll_after_init PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_select_after_init(dut):
#     """Send SELECT with UID → expect SAK + CRC_A (3 bytes) after init."""
#     _ = await setup(dut)
#
#     # Wait for init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     result = await mfrc_select(dut, MOCK_UID)
#
#     assert result["ok"], f"SELECT failed: error={result['error']:#04x}"
#     assert result["rx_len"] == 3, f"Expected 3 bytes, got {result['rx_len']}"
#     assert (
#         result["rx_data"][0] == 0x08
#     ), f"Expected SAK=0x08, got {result['rx_data'][0]:#04x}"
#
#     dut._log.info("test_mfrc_select_after_init PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_card_activate_sequence(dut):
#     """Full card activation after init: REQA → ANTICOLL → SELECT."""
#     _ = await setup(dut)
#
#     # Wait for init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     # Full activation sequence
#     result = await mfrc_reqa(dut)
#     assert result["ok"], "REQA failed"
#     assert result["rx_data"] == [0x04, 0x00], f"Expected ATQA, got {result['rx_data']}"
#
#     result = await mfrc_anticoll(dut)
#     assert result["ok"], "ANTICOLL failed"
#     uid = result["rx_data"][:4]
#     assert uid == MOCK_UID, f"Expected UID {MOCK_UID}, got {uid}"
#
#     result = await mfrc_select(dut, uid)
#     assert result["ok"], "SELECT failed"
#     assert result["rx_data"][0] == 0x08, f"Expected SAK=0x08"
#
#     dut._log.info("test_mfrc_card_activate_sequence PASSED ✓")
#
#
# # ---------------------------------------------------------------------------
# # Test: Simultaneous requests – first pair
# # ---------------------------------------------------------------------------
#
#
# @cocotb.test()
# async def test_simultaneous_first_grant_default(dut):
#     """
#     When both clients request at the same time (from reset),
#     rr_pref=0 so client A should be granted first, then B.
#
#     Wait for MFRC init to complete first.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     # Launch both transactions concurrently
#     eeprom_task = cocotb.start_soon(eeprom_send_cmd(dut, 1))
#     mfrc_task = cocotb.start_soon(mfrc_reqa(dut))
#
#     eeprom_result = await eeprom_task
#     mfrc_result = await mfrc_task
#
#     # Both should succeed
#     expected_key = int.from_bytes(KEY_A, byteorder="big")
#     assert (
#         eeprom_result == expected_key
#     ), f"EEPROM read failed: expected {expected_key:#x}, got {eeprom_result:#x}"
#     assert mfrc_result["ok"], f"MFRC REQA failed: error={mfrc_result['error']:#04x}"
#     assert mfrc_result["rx_data"] == [
#         0x04,
#         0x00,
#     ], f"Expected ATQA, got {mfrc_result['rx_data']}"
#
#
# @cocotb.test()
# async def test_simultaneous_first_grant_alternates(dut):
#     """
#     Two back-to-back simultaneous requests should alternate:
#     Round 1: A first (rr_pref starts at 0), then B
#     Round 2: B first (rr_pref flipped), then A
#
#     We verify both complete successfully each time.
#     Wait for MFRC init to complete first.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     # --- Round 1: both request simultaneously ---
#     e1 = cocotb.start_soon(eeprom_send_cmd(dut, 1))
#     m1 = cocotb.start_soon(mfrc_reqa(dut))
#     r_e1 = await e1
#     r_m1 = await m1
#
#     expected_key = int.from_bytes(KEY_A, byteorder="big")
#     assert r_e1 == expected_key, f"Round 1 EEPROM failed"
#     assert r_m1["ok"], f"Round 1 MFRC failed"
#
#     # --- Round 2: both request simultaneously again ---
#     e2 = cocotb.start_soon(eeprom_send_cmd(dut, 0))
#     m2 = cocotb.start_soon(mfrc_reqa(dut))
#     r_e2 = await e2
#     r_m2 = await m2
#
#     expected_id = int.from_bytes(ID_A, byteorder="big")
#     assert r_e2 == expected_id, f"Round 2 EEPROM failed"
#     assert r_m2["ok"], f"Round 2 MFRC failed"
#
#
# # ---------------------------------------------------------------------------
# # Test: Sequential single-client requests (no contention)
# # ---------------------------------------------------------------------------
#
#
# @cocotb.test()
# async def test_eeprom_then_mfrc_no_contention(dut):
#     """
#     Client A finishes, then client B requests. No arbitration conflict.
#     Both should succeed normally.
#     Wait for MFRC init to complete first.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     # EEPROM first (no contention)
#     result_a = await eeprom_send_cmd(dut, 1)
#     expected_key = int.from_bytes(KEY_A, byteorder="big")
#     assert result_a == expected_key, f"EEPROM read failed"
#
#     # MFRC second (no contention)
#     result_b = await mfrc_reqa(dut)
#     assert result_b["ok"], f"MFRC REQA failed"
#     assert result_b["rx_data"] == [0x04, 0x00]
#
#
# @cocotb.test()
# async def test_mfrc_then_eeprom_no_contention(dut):
#     """
#     Client B finishes, then client A requests. No arbitration conflict.
#     Wait for MFRC init to complete first.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     result_b = await mfrc_reqa(dut)
#     assert result_b["ok"], f"MFRC REQA failed"
#
#     result_a = await eeprom_send_cmd(dut, 0)
#     expected_id = int.from_bytes(ID_A, byteorder="big")
#     assert result_a == expected_id, f"EEPROM read failed"
#
#
# # ---------------------------------------------------------------------------
# # Test: Repeated back-to-back single-client doesn't starve
# # ---------------------------------------------------------------------------
#
#
# @cocotb.test()
# async def test_eeprom_back_to_back(dut):
#     """
#     Multiple EEPROM transactions in a row (no MFRC contention).
#     Ensures the arbiter doesn't get stuck after repeated same-client use.
#     """
#     await setup(dut)
#
#     for i in range(4):
#         get_key = i % 2  # alternate key/id reads
#         result = await eeprom_send_cmd(dut, get_key)
#         if get_key:
#             expected = int.from_bytes(KEY_A, byteorder="big")
#         else:
#             expected = int.from_bytes(ID_A, byteorder="big")
#         assert result == expected, f"EEPROM iteration {i} failed"
#
#
# @cocotb.test()
# async def test_mfrc_back_to_back(dut):
#     """
#     Multiple MFRC transactions in a row (no EEPROM contention).
#     Wait for MFRC init to complete first.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     for i in range(4):
#         result = await mfrc_reqa(dut)
#         assert result["ok"], f"MFRC iteration {i} failed: error={result['error']:#04x}"
#         assert result["rx_data"] == [0x04, 0x00], f"MFRC iteration {i} bad ATQA"
#
#
# # ---------------------------------------------------------------------------
# # Test: Fairness over many simultaneous requests
# # ---------------------------------------------------------------------------
#
#
# @cocotb.test()
# async def test_fairness_many_simultaneous(dut):
#     """
#     Launch 6 rounds of simultaneous requests. All should complete
#     successfully, demonstrating the arbiter doesn't favor one client.
#     Wait for MFRC init to complete first.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     expected_key = int.from_bytes(KEY_A, byteorder="big")
#     expected_id = int.from_bytes(ID_A, byteorder="big")
#
#     for i in range(6):
#         get_key = i % 2
#         e = cocotb.start_soon(eeprom_send_cmd(dut, get_key))
#         m = cocotb.start_soon(mfrc_reqa(dut))
#
#         r_e = await e
#         r_m = await m
#
#         expected = expected_key if get_key else expected_id
#         assert r_e == expected, f"Round {i} EEPROM failed"
#         assert r_m["ok"], f"Round {i} MFRC failed"
#
#
# # ---------------------------------------------------------------------------
# # Test: Interleaved — one client mid-transaction, other arrives
# # ---------------------------------------------------------------------------
#
#
# @cocotb.test()
# async def test_mfrc_arrives_during_eeprom(dut):
#     """
#     Start an EEPROM read, then while it's in-flight start an MFRC request.
#     The MFRC should wait and then succeed after EEPROM completes.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     # Start EEPROM (will take many SPI clocks)
#     eeprom_task = cocotb.start_soon(eeprom_send_cmd(dut, 1))
#
#     # Wait a few clocks so EEPROM is mid-transaction
#     for _ in range(50):
#         await RisingEdge(dut.clk)
#
#     # Now start MFRC — should be queued
#     mfrc_task = cocotb.start_soon(mfrc_reqa(dut))
#
#     r_e = await eeprom_task
#     r_m = await mfrc_task
#
#     expected_key = int.from_bytes(KEY_A, byteorder="big")
#     assert r_e == expected_key, f"EEPROM read failed"
#     assert r_m["ok"], f"MFRC REQA failed after waiting"
#
#
# @cocotb.test()
# async def test_eeprom_arrives_during_mfrc(dut):
#     """
#     Start an MFRC REQA, then while it's in-flight start an EEPROM request.
#     The EEPROM should wait and then succeed after MFRC completes.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     mfrc_task = cocotb.start_soon(mfrc_reqa(dut))
#
#     for _ in range(50):
#         await RisingEdge(dut.clk)
#
#     eeprom_task = cocotb.start_soon(eeprom_send_cmd(dut, 0))
#
#     r_m = await mfrc_task
#     r_e = await eeprom_task
#
#     assert r_m["ok"], f"MFRC REQA failed"
#     expected_id = int.from_bytes(ID_A, byteorder="big")
#     assert r_e == expected_id, f"EEPROM read failed after waiting"
#
#
# # ---------------------------------------------------------------------------
# # Test: Rapid alternating requests (A, B, A, B without overlap)
# # ---------------------------------------------------------------------------
#
#
# @cocotb.test()
# async def test_rapid_alternating(dut):
#     """
#     Quickly alternate: EEPROM → MFRC → EEPROM → MFRC, each sequential.
#     Verifies arbiter state doesn't get corrupted by rapid switching.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     expected_key = int.from_bytes(KEY_A, byteorder="big")
#
#     for i in range(4):
#         if i % 2 == 0:
#             r = await eeprom_send_cmd(dut, 1)
#             assert r == expected_key, f"Step {i} EEPROM failed"
#         else:
#             r = await mfrc_reqa(dut)
#             assert r["ok"], f"Step {i} MFRC failed"
#
#
# # ---------------------------------------------------------------------------
# # Test: MFRC ANTICOLL with simultaneous EEPROM
# # ---------------------------------------------------------------------------
#
#
# @cocotb.test()
# async def test_anticoll_simultaneous_with_eeprom(dut):
#     """
#     Simultaneous ANTICOLL (longer MFRC transaction) + EEPROM read.
#     Tests that longer multi-byte SPI transactions also work under contention.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     eeprom_task = cocotb.start_soon(eeprom_send_cmd(dut, 1))
#     mfrc_task = cocotb.start_soon(mfrc_anticoll(dut))
#
#     r_e = await eeprom_task
#     r_m = await mfrc_task
#
#     expected_key = int.from_bytes(KEY_A, byteorder="big")
#     assert r_e == expected_key, f"EEPROM failed"
#     assert r_m["ok"], f"ANTICOLL failed"
#     assert r_m["rx_len"] == 5, f"Expected 5 bytes UID+BCC, got {r_m['rx_len']}"
#
#
# # ---------------------------------------------------------------------------
# # Test: Stress — many simultaneous rounds with varied operations
# # ---------------------------------------------------------------------------
#
#
# @cocotb.test()
# async def test_stress_mixed_operations(dut):
#     """
#     Stress test: 8 rounds of simultaneous requests mixing different
#     EEPROM addresses and MFRC commands.
#     """
#     await setup(dut)
#
#     # Wait for MFRC init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#
#     expected_key = int.from_bytes(KEY_A, byteorder="big")
#     expected_id = int.from_bytes(ID_A, byteorder="big")
#
#     operations = [
#         (1, "reqa"),
#         (0, "reqa"),
#         (1, "anticoll"),
#         (0, "anticoll"),
#         (1, "reqa"),
#         (0, "reqa"),
#         (1, "anticoll"),
#         (0, "anticoll"),
#     ]
#
#     for i, (get_key, mfrc_op) in enumerate(operations):
#         if mfrc_op == "reqa":
#             mfrc_coro = mfrc_reqa(dut)
#         else:
#             mfrc_coro = mfrc_anticoll(dut)
#
#         eeprom_task = cocotb.start_soon(eeprom_send_cmd(dut, get_key))
#         mfrc_task = cocotb.start_soon(mfrc_coro)
#
#         r_e = await eeprom_task
#         r_m = await mfrc_task
#
#         expected = expected_key if get_key else expected_id
#         assert r_e == expected, f"Round {i} EEPROM (get_key={get_key}) failed"
#         assert r_m["ok"], f"Round {i} MFRC ({mfrc_op}) failed"
#
#         if mfrc_op == "reqa":
#             assert r_m["rx_data"] == [
#                 0x04,
#                 0x00,
#             ], f"Round {i} bad ATQA: {r_m['rx_data']}"
#         else:
#             assert (
#                 r_m["rx_len"] == 5
#             ), f"Round {i} ANTICOLL expected 5 bytes, got {r_m['rx_len']}"


#
# Runner
#


def test_spi_e2e_runner():
    sim = os.getenv("SIM", "icarus")
    spi_module_path = Path(__file__).resolve().parent.parent.parent
    src_dir = spi_module_path / "src"

    sources = list(src_dir.glob("*.sv"))

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
