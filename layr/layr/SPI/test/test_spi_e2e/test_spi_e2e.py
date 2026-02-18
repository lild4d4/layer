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


@cocotb.test()
async def test_eeprom_back_to_back(dut):
    """
    Multiple EEPROM transactions in a row (no MFRC contention).
    Ensures the arbiter doesn't get stuck after repeated same-client use.
    """
    await setup(dut)

    for i in range(4):
        get_key = i % 2  # alternate key/id reads
        result = await eeprom_send_cmd(dut, get_key)
        if get_key:
            expected = int.from_bytes(KEY_A, byteorder="big")
        else:
            expected = int.from_bytes(ID_A, byteorder="big")
        assert result == expected, f"EEPROM iteration {i} failed"


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

    dut._log.info(f"init_done={dut.mfrc_init_done.value}")
    dut._log.info("test_mfrc_auto_init PASSED ✓")


@cocotb.test()
async def test_mfrc_auto_card_detection(dut):
    """Verify that card_present goes high when card is detected via auto-poll."""
    _ = await setup(dut)
    dut._log.info("Waiting for MFRC auto-initialization and card detection...")

    # Wait for init to complete
    init_ok = await mfrc_wait_for_init(dut, timeout_us=200000)
    assert init_ok, "MFRC auto-init did not complete in time"

    # Wait for card to be detected (auto-poll runs after init)
    card_detected = await mfrc_wait_for_card(dut, timeout_us=300000)
    assert card_detected, "Card was not detected in time"

    assert dut.mfrc_card_present.value == 1, "card_present should be 1"
    assert (
        int(dut.mfrc_atqa.value) == 0x0400
    ), f"Expected ATQA=0x0400, got {int(dut.mfrc_atqa.value):#06x}"

    dut._log.info(
        f"card_present={dut.mfrc_card_present.value}, atqa={int(dut.mfrc_atqa.value):#06x}"
    )
    dut._log.info("test_mfrc_auto_card_detection PASSED ✓")


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
