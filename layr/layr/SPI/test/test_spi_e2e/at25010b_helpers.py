from pathlib import Path
from cocotb.triggers import RisingEdge
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from test_at25010b.at25010b_mock import AT25010B_EEPROM
from helpers import build_spi_bus, wait_done

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
