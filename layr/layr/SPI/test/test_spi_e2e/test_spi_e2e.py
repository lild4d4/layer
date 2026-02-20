import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from at25010b_helpers import eeprom_setup, eeprom_send_cmd, KEY_A, ID_A
from mfrc522_helpers import (
    mfrc_setup,
    mfrc_reqa,
    mfrc_anticoll,
    mfrc_select,
    mfrc_rats,
    mfrc_wupa,
    mfrc_wait_for_init,
    mfrc_wait_for_card,
)
from helpers import reset_dut
from cocotb_tools.runner import get_runner

CLK_PERIOD_NS = 10  # 100MHz


def dump_hex(mfrc, test_name):
    with open(f"{test_name}_sent.hex", "w") as f:
        for b in mfrc.get_spi_bytes_sent():
            f.write(f"{b:02X}\n")
    with open(f"{test_name}_received.hex", "w") as f:
        for b in mfrc.get_spi_bytes_received():
            f.write(f"{b:02X}\n")


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    eeprom = await eeprom_setup(dut)
    mfrc = await mfrc_setup(dut)

    await reset_dut(dut)

    return (eeprom, mfrc)


# =============================================================================
# AT25010B EEPROM Tests
# =============================================================================

#
# @cocotb.test()
# async def test_eeprom_get_key(dut):
#     """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
#     _ = await setup(dut)
#
#     result = await eeprom_send_cmd(dut, 1)
#     expected = int.from_bytes(KEY_A, byteorder="big")
#     assert result == expected, f"Expected {expected:#x}, got {result:#x}"
#
#
# @cocotb.test()
# async def test_eeprom_get_id(dut):
#     """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
#     _ = await setup(dut)
#
#     result = await eeprom_send_cmd(dut, 0)
#     expected = int.from_bytes(ID_A, byteorder="big")
#     assert result == expected, f"Expected {expected:#x}, got {result:#x}"
#
#
# @cocotb.test()
# async def test_eeprom_conseq(dut):
#     """Read 128 bits (16 bytes) from EEPROM starting at address 0x00."""
#     _ = await setup(dut)
#
#     result = await eeprom_send_cmd(dut, 0)
#     expected = int.from_bytes(ID_A, byteorder="big")
#     assert result == expected, f"1: Expected {expected:#x}, got {result:#x}"
#
#     result = await eeprom_send_cmd(dut, 1)
#     expected = int.from_bytes(KEY_A, byteorder="big")
#     assert result == expected, f"2: Expected {expected:#x}, got {result:#x}"
#
#     result = await eeprom_send_cmd(dut, 1)
#     expected = int.from_bytes(KEY_A, byteorder="big")
#     assert result == expected, f"3: Expected {expected:#x}, got {result:#x}"
#
#     result = await eeprom_send_cmd(dut, 0)
#     expected = int.from_bytes(ID_A, byteorder="big")
#     assert result == expected, f"4: Expected {expected:#x}, got {result:#x}"
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
# # =============================================================================
# # MFRC522 Auto-Init and Card Detection Tests
# # =============================================================================
#
#
# MOCK_UID = [0xDE, 0xAD, 0xBE, 0xEF]
#
#
# @cocotb.test()
# async def test_mfrc_auto_init(dut):
#     """Verify that mfrc_init_done goes high after auto-initialization."""
#     _ = await setup(dut)
#     dut._log.info("Waiting for MFRC auto-initialization...")
#
#     # Wait for init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#
#     assert init_ok, "MFRC auto-init did not complete in time"
#     assert dut.mfrc_init_done.value == 1, "init_done should be 1"
#
#     dut._log.info(f"init_done={dut.mfrc_init_done.value}")
#     dut._log.info("test_mfrc_auto_init PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_auto_card_detection(dut):
#     """Verify that card_present goes high when card is detected via auto-poll."""
#     _ = await setup(dut)
#     dut._log.info("Waiting for MFRC auto-initialization and card detection...")
#
#     # Wait for init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete in time"
#
#     # Wait for card to be detected (auto-poll runs after init)
#     card_detected = await mfrc_wait_for_card(dut, timeout_us=300000)
#     assert card_detected, "Card was not detected in time"
#
#     assert dut.mfrc_card_present.value == 1, "card_present should be 1"
#     assert (
#         int(dut.mfrc_atqa.value) == 0x0400
#     ), f"Expected ATQA=0x0400, got {int(dut.mfrc_atqa.value):#06x}"
#
#     dut._log.info(
#         f"card_present={dut.mfrc_card_present.value}, atqa={int(dut.mfrc_atqa.value):#06x}"
#     )
#     dut._log.info("test_mfrc_auto_card_detection PASSED ✓")
#


@cocotb.test()
async def test_mfrc_delayed_card_detection(dut):
    """
    Test card detection with 5 polling cycles before card appears.
    Verifies auto-poll continues working when card is not initially present.
    """
    _, mfrc = await setup(dut)
    dut._log.info("Testing delayed card detection...")

    # Wait for init to complete
    init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
    assert init_ok, "MFRC auto-init did not complete in time"
    dut._log.info("MFRC auto-init complete")

    # Disable card presence - simulate no card nearby
    mfrc.set_card_present(False)
    dut._log.info("Card presence disabled - simulating no card nearby")

    # Wait for 5 polling cycles (each cycle is ~50ms based on auto-poll timing)
    # We'll wait for 5 failed polls - polling happens at regular intervals
    POLL_CYCLE_US = 50000  # 50ms per poll cycle
    num_polls = 5
    for i in range(num_polls):
        dut._log.info(f"Waiting for poll cycle {i + 1}/{num_polls}...")
        await RisingEdge(dut.clk)
        await Timer(POLL_CYCLE_US, unit="ns")

    dut._log.info(f"Completed {num_polls} polling cycles with no card")

    # Now make card appear
    mfrc.set_card_present(True)
    dut._log.info("Card now present - enabling card detection")

    # Wait for card to be detected
    card_detected = await mfrc_wait_for_card(dut, timeout_us=300000)
    assert card_detected, "Card was not detected after becoming present"

    assert dut.mfrc_card_present.value == 1, "card_present should be 1"
    assert int(dut.mfrc_atqa.value) == 0x0400, (
        f"Expected ATQA=0x0400, got {int(dut.mfrc_atqa.value):#06x}"
    )

    dut._log.info(
        f"card_present={dut.mfrc_card_present.value}, atqa={int(dut.mfrc_atqa.value):#06x}"
    )
    dut._log.info("test_mfrc_delayed_card_detection PASSED ✓")

    dump_hex(mfrc, "1____test_mfrc_delayed_card_detection")


@cocotb.test()
async def test_mfrc_rats_transceive(dut):
    """Verify dedicated RATS path returns ATS bytes."""
    _, _ = await setup(dut)

    init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
    assert init_ok, "MFRC auto-init did not complete in time"

    card_ok = await mfrc_wait_for_card(dut, timeout_us=300000)
    assert card_ok, "Card was not detected in time"

    ats = await mfrc_rats(dut)
    assert ats is not None, "No ATS response received"
    assert len(ats) >= 3, f"ATS too short: {len(ats)}"
    assert ats[0] > 0, "Invalid ATS length byte"


# =============================================================================
# MFRC522 Transceive / PICC Communication Tests
# =============================================================================


# @cocotb.test()
# async def test_mfrc_transceive_reqa(dut):
#     """
#     Test standalone REQA transceive command.
#     Sends REQA (0x26) and expects ATQA (0x04 0x00) response.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing REQA transceive...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     # Send REQA manually
#     atqa = await mfrc_reqa(dut)
#
#     assert atqa is not None, "No ATQA response received"
#     assert atqa == 0x0400, f"Expected ATQA=0x0400, got {atqa:#06x}"
#
#     dut._log.info(f"REQA -> ATQA={atqa:#06x}")
#     dut._log.info("test_mfrc_transceive_reqa PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_transceive_wupa(dut):
#     """
#     Test WUPA transceive command.
#     Sends WUPA (0x52) and expects ATQA (0x04 0x00) response.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing WUPA transceive...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     # Send WUPA manually
#     atqa = await mfrc_wupa(dut)
#
#     assert atqa is not None, "No ATQA response received"
#     assert atqa == 0x0400, f"Expected ATQA=0x0400, got {atqa:#06x}"
#
#     dut._log.info(f"WUPA -> ATQA={atqa:#06x}")
#     dut._log.info("test_mfrc_transceive_wupa PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_transceive_anticoll(dut):
#     """
#     Test ANTICOLLISION command sequence.
#     Sends REQA, then ANTICOLL CL1, expects UID + BCC.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing ANTICOLLISION transceive...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     # Step 1: REQA
#     atqa = await mfrc_reqa(dut)
#     assert atqa is not None, "No ATQA response"
#     assert atqa == 0x0400, f"Expected ATQA=0x0400, got {atqa:#06x}"
#
#     # Step 2: ANTICOLL CL1
#     uid_bcc = await mfrc_anticoll(dut)
#     assert uid_bcc is not None, "No ANTICOLL response"
#
#     # Verify UID matches mock
#     expected_uid = bytes(MOCK_UID)
#     expected_bcc = MOCK_UID[0] ^ MOCK_UID[1] ^ MOCK_UID[2] ^ MOCK_UID[3]
#
#     received_uid = uid_bcc[:4]
#     received_bcc = uid_bcc[4]
#
#     assert (
#         received_uid == expected_uid
#     ), f"UID mismatch: expected {expected_uid.hex()}, got {received_uid.hex()}"
#     assert (
#         received_bcc == expected_bcc
#     ), f"BCC mismatch: expected {expected_bcc:#04x}, got {received_bcc:#04x}"
#
#     dut._log.info(f"ANTICOLL -> UID={received_uid.hex()}, BCC={received_bcc:#04x}")
#     dut._log.info("test_mfrc_transceive_anticoll PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_transceive_select(dut):
#     """
#     Test full SELECT sequence: REQA -> ANTICOLL -> SELECT.
#     Expects SAK response after SELECT.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing SELECT transceive sequence...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     # Step 1: REQA
#     atqa = await mfrc_reqa(dut)
#     assert atqa == 0x0400, f"REQA failed: ATQA={atqa:#06x}"
#
#     # Step 2: ANTICOLL CL1
#     uid_bcc = await mfrc_anticoll(dut)
#     assert uid_bcc is not None, "ANTICOLL failed"
#
#     uid = uid_bcc[:4]
#     bcc = uid_bcc[4]
#
#     # Step 3: SELECT CL1
#     sak = await mfrc_select(dut, uid, bcc)
#     assert sak is not None, "No SAK response"
#
#     # SAK for MIFARE Classic 1K = 0x08
#     assert sak == 0x08, f"Expected SAK=0x08, got {sak:#04x}"
#
#     dut._log.info(f"SELECT -> SAK={sak:#04x}")
#     dut._log.info("test_mfrc_transceive_select PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_full_card_identification(dut):
#     """
#     Complete card identification sequence:
#     REQA -> ANTICOLL -> SELECT -> verify full UID.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing full card identification...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     # Full sequence
#     atqa = await mfrc_reqa(dut)
#     assert atqa == 0x0400
#
#     uid_bcc = await mfrc_anticoll(dut)
#     assert uid_bcc, "INTERNAL TEST EXCEPTION"
#
#     uid = uid_bcc[:4]
#     bcc = uid_bcc[4]
#
#     sak = await mfrc_select(dut, uid, bcc)
#     assert sak == 0x08
#
#     # Verify complete UID
#     expected_uid = bytes(MOCK_UID)
#     assert uid == expected_uid, f"UID mismatch: {uid.hex()} != {expected_uid.hex()}"
#
#     dut._log.info(f"Card identified: UID={uid.hex()}, SAK={sak:#04x}")
#     dut._log.info("test_mfrc_full_card_identification PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_multiple_reqa(dut):
#     """
#     Test multiple consecutive REQA commands.
#     Ensures transceive state machine resets properly between commands.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing multiple REQA commands...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     for i in range(5):
#         atqa = await mfrc_reqa(dut)
#         assert atqa == 0x0400, f"REQA #{i + 1} failed: ATQA={atqa}"
#         dut._log.info(f"REQA #{i + 1} -> ATQA={atqa:#06x}")
#
#     dut._log.info("test_mfrc_multiple_reqa PASSED ✓")
#
#
# # =============================================================================
# # SPI Arbiter Tests - Concurrent Access
# # =============================================================================
#
#
# @cocotb.test()
# async def test_arb_eeprom_during_mfrc_init(dut):
#     """
#     Test EEPROM access while MFRC522 is initializing.
#     Verifies arbiter handles concurrent requests from different clients.
#     """
#     await setup(dut)
#     dut._log.info("Testing EEPROM access during MFRC init...")
#
#     # Don't wait for init - start EEPROM read immediately
#     # MFRC init should be running in background
#
#     # Read EEPROM while MFRC is initializing
#     result = await eeprom_send_cmd(dut, 1)
#     expected = int.from_bytes(KEY_A, byteorder="big")
#     assert result == expected, f"EEPROM read failed during MFRC init"
#
#     # Now wait for init to complete
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC init should still complete"
#
#     dut._log.info("test_arb_eeprom_during_mfrc_init PASSED ✓")
#
#
# @cocotb.test()
# async def test_arb_eeprom_during_card_poll(dut):
#     """
#     Test EEPROM access while MFRC522 is polling for cards.
#     Arbiter should interleave EEPROM and MFRC transactions.
#     """
#     await setup(dut)
#     dut._log.info("Testing EEPROM access during card polling...")
#
#     # Wait for init
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC init failed"
#
#     # Card polling should be running now
#     # Interleave EEPROM reads
#     for i in range(3):
#         get_key = i % 2
#         result = await eeprom_send_cmd(dut, get_key)
#         if get_key:
#             expected = int.from_bytes(KEY_A, byteorder="big")
#         else:
#             expected = int.from_bytes(ID_A, byteorder="big")
#         assert result == expected, f"EEPROM read #{i + 1} failed during polling"
#         dut._log.info(f"EEPROM read #{i + 1} OK during card poll")
#
#     # Card should still be detectable
#     card_detected = await mfrc_wait_for_card(dut, timeout_us=300000)
#     assert card_detected, "Card detection should work after EEPROM accesses"
#
#     dut._log.info("test_arb_eeprom_during_card_poll PASSED ✓")
#
#
# @cocotb.test()
# async def test_arb_interleaved_operations(dut):
#     """
#     Interleave EEPROM reads with MFRC PICC commands.
#     Tests arbiter fairness and state isolation.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing interleaved EEPROM and MFRC operations...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     # Interleaved sequence
#     # 1. EEPROM read
#     result = await eeprom_send_cmd(dut, 1)
#     assert result == int.from_bytes(KEY_A, byteorder="big"), "EEPROM KEY read failed"
#     dut._log.info("Step 1: EEPROM KEY read OK")
#
#     # 2. MFRC REQA
#     atqa = await mfrc_reqa(dut)
#     assert atqa == 0x0400, "REQA failed"
#     dut._log.info("Step 2: MFRC REQA OK")
#
#     # 3. EEPROM read
#     result = await eeprom_send_cmd(dut, 0)
#     assert result == int.from_bytes(ID_A, byteorder="big"), "EEPROM ID read failed"
#     dut._log.info("Step 3: EEPROM ID read OK")
#
#     # 4. MFRC ANTICOLL
#     uid_bcc = await mfrc_anticoll(dut)
#     assert uid_bcc is not None, "ANTICOLL failed"
#     dut._log.info("Step 4: MFRC ANTICOLL OK")
#
#     # 5. EEPROM read
#     result = await eeprom_send_cmd(dut, 1)
#     assert result == int.from_bytes(KEY_A, byteorder="big"), "EEPROM KEY read failed"
#     dut._log.info("Step 5: EEPROM KEY read OK")
#
#     # 6. MFRC SELECT
#     uid = uid_bcc[:4]
#     bcc = uid_bcc[4]
#     sak = await mfrc_select(dut, uid, bcc)
#     assert sak == 0x08, "SELECT failed"
#     dut._log.info("Step 6: MFRC SELECT OK")
#
#     dut._log.info("test_arb_interleaved_operations PASSED ✓")
#
#
# @cocotb.test()
# async def test_arb_rapid_switching(dut):
#     """
#     Rapidly alternate between EEPROM and MFRC commands.
#     Stress test for arbiter grant/release logic.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing rapid arbiter switching...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     for i in range(10):
#         # EEPROM
#         result = await eeprom_send_cmd(dut, i % 2)
#         if i % 2:
#             expected = int.from_bytes(KEY_A, byteorder="big")
#         else:
#             expected = int.from_bytes(ID_A, byteorder="big")
#         assert result == expected, f"EEPROM #{i} failed"
#
#         # MFRC REQA
#         atqa = await mfrc_reqa(dut)
#         assert atqa == 0x0400, f"REQA #{i} failed"
#
#     dut._log.info("test_arb_rapid_switching PASSED ✓")
#
#
# @cocotb.test()
# async def test_arb_burst_eeprom_then_mfrc(dut):
#     """
#     Burst of EEPROM reads followed by MFRC sequence.
#     Ensures arbiter releases properly after burst.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing burst EEPROM then MFRC...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     # Burst EEPROM reads
#     for i in range(8):
#         result = await eeprom_send_cmd(dut, i % 2)
#         if i % 2:
#             expected = int.from_bytes(KEY_A, byteorder="big")
#         else:
#             expected = int.from_bytes(ID_A, byteorder="big")
#         assert result == expected, f"EEPROM burst #{i} failed"
#
#     dut._log.info("EEPROM burst complete")
#
#     # Full MFRC sequence
#     atqa = await mfrc_reqa(dut)
#     assert atqa == 0x0400
#
#     uid_bcc = await mfrc_anticoll(dut)
#     assert uid_bcc is not None
#
#     sak = await mfrc_select(dut, uid_bcc[:4], uid_bcc[4])
#     assert sak == 0x08
#
#     dut._log.info("MFRC sequence after burst complete")
#     dut._log.info("test_arb_burst_eeprom_then_mfrc PASSED ✓")
#
#
# @cocotb.test()
# async def test_arb_burst_mfrc_then_eeprom(dut):
#     """
#     Multiple MFRC transactions followed by EEPROM reads.
#     Ensures arbiter releases properly after MFRC burst.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing burst MFRC then EEPROM...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     # Multiple MFRC REQA commands
#     for i in range(5):
#         atqa = await mfrc_reqa(dut)
#         assert atqa == 0x0400, f"REQA #{i} failed"
#
#     dut._log.info("MFRC REQA burst complete")
#
#     # Full card identification
#     atqa = await mfrc_reqa(dut)
#     uid_bcc = await mfrc_anticoll(dut)
#     assert uid_bcc, "INTERNAL TEST EXCEPTION"
#     sak = await mfrc_select(dut, uid_bcc[:4], uid_bcc[4])
#     assert sak == 0x08
#
#     dut._log.info("MFRC SELECT complete")
#
#     # Now EEPROM reads
#     for i in range(4):
#         result = await eeprom_send_cmd(dut, i % 2)
#         if i % 2:
#             expected = int.from_bytes(KEY_A, byteorder="big")
#         else:
#             expected = int.from_bytes(ID_A, byteorder="big")
#         assert result == expected, f"EEPROM #{i} after MFRC burst failed"
#
#     dut._log.info("EEPROM reads after MFRC burst complete")
#     dut._log.info("test_arb_burst_mfrc_then_eeprom PASSED ✓")
#
#
# # =============================================================================
# # Edge Cases and Error Handling
# # =============================================================================
#
#
# @cocotb.test()
# async def test_mfrc_reqa_after_select(dut):
#     """
#     Test that REQA works after a complete SELECT sequence.
#     Card should return to IDLE/READY state.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing REQA after SELECT...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     # Full SELECT sequence
#     _ = await mfrc_reqa(dut)
#     uid_bcc = await mfrc_anticoll(dut)
#     assert uid_bcc, "INTERNAL TEST EXCEPTION"
#
#     sak = await mfrc_select(dut, uid_bcc[:4], uid_bcc[4])
#     assert sak == 0x08
#
#     dut._log.info("First SELECT complete")
#
#     # WUPA should wake up the card (REQA only works on IDLE cards)
#     atqa2 = await mfrc_wupa(dut)
#     assert atqa2 == 0x0400, f"WUPA after SELECT failed: {atqa2}"
#
#     dut._log.info("WUPA after SELECT OK")
#     dut._log.info("test_mfrc_reqa_after_select PASSED ✓")
#
#
# @cocotb.test()
# async def test_mfrc_repeated_select_sequence(dut):
#     """
#     Perform multiple complete card identification sequences.
#     Tests full state machine cycling.
#     """
#     _ = await setup(dut)
#     dut._log.info("Testing repeated SELECT sequences...")
#
#     # Wait for init + card
#     init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
#     assert init_ok, "MFRC auto-init did not complete"
#     dut._log.info("MFRC auto-init complete")
#     card_ok = await mfrc_wait_for_card(dut, timeout_us=200000)
#     assert card_ok, "MFRC card-ok did not complete"
#     dut._log.info("MFRC card-ok complete")
#
#     for i in range(3):
#         # Use WUPA to ensure card responds even if in HALT state
#         atqa = await mfrc_wupa(dut)
#         assert atqa == 0x0400, f"Sequence #{i + 1}: WUPA failed"
#
#         uid_bcc = await mfrc_anticoll(dut)
#         assert uid_bcc is not None, f"Sequence #{i + 1}: ANTICOLL failed"
#
#         sak = await mfrc_select(dut, uid_bcc[:4], uid_bcc[4])
#         assert sak == 0x08, f"Sequence #{i + 1}: SELECT failed"
#
#         dut._log.info(f"SELECT sequence #{i + 1} complete")
#
#     dut._log.info("test_mfrc_repeated_select_sequence PASSED ✓")
#

# =============================================================================
# Runner
# =============================================================================


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
