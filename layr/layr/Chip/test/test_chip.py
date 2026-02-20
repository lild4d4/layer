import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout
from cocotb_tools.runner import get_runner
from cocotbext.spi import SpiBus
from Crypto.Cipher import AES


os.environ["COCOTB_ANSI_OUTPUT"] = "1"


PROJ_ROOT = Path(__file__).resolve().parent.parent.parent
SPI_TEST_ROOT = PROJ_ROOT / "SPI" / "test"
sys.path.insert(0, str(SPI_TEST_ROOT))

from test_at25010b.at25010b_mock import AT25010B_EEPROM  # noqa: E402
from test_mfrc522.mock_mfrc522 import Mfrc522SpiSlave  # noqa: E402


KEY_A = bytes.fromhex("39558d1f193656ab8b4b65e25ac48474")
CARD_ID = bytes.fromhex("bbe8278a67f960605adafd6f63cf7ba7")
RC = bytes.fromhex("1111cafeaffe1111")


class LayrCardMock(Mfrc522SpiSlave):
    def __init__(self, bus, *, key: bytes, card_id: bytes, get_session_key):
        super().__init__(bus)
        self._key = key
        self._card_id = card_id
        self._get_session_key = get_session_key

    def _process_picc_command(self, req: bytes, tx_last_bits: int):
        req_stripped = req.rstrip(b"\x00")

        # RATS
        if req_stripped == b"\xe0\x50":
            return bytes.fromhex("0A788091028073C82110C392"), 0

        # ISO-DEP I-Block
        if len(req_stripped) >= 2 and req_stripped[0] in (0x02, 0x03):
            pcb = req_stripped[0]
            inf = req_stripped[1:]

            # SELECT app
            if inf == bytes.fromhex("00A4040006F000000CDC00"):
                return bytes([pcb ^ 0x01, 0x90, 0x00]), 0

            # APDUs
            if len(inf) >= 2 and inf[0] == 0x80:
                ins = inf[1]

                # AUTH_INIT -> return encrypted seed/challenge block
                if ins == 0x10:
                    plain = RC + (b"\x00" * 8)
                    card_cipher = AES.new(self._key, AES.MODE_ECB).encrypt(plain)
                    return bytes([pcb ^ 0x01]) + card_cipher, 0

                # AUTH -> ACK only
                if ins == 0x11:
                    return bytes([pcb ^ 0x01, 0x90, 0x00]), 0

                # GET_ID -> encrypt card ID with current session key from DUT
                if ins == 0x12:
                    session_key = self._get_session_key()
                    cocotb.log.info(f"LayrCardMock session_key={session_key.hex()}")
                    id_cipher = AES.new(session_key, AES.MODE_ECB).encrypt(
                        self._card_id
                    )
                    return bytes([pcb ^ 0x01]) + id_cipher, 0

        # Keep REQA / ANTICOLL / SELECT behavior from base model.
        return super()._process_picc_command(req, tx_last_bits)


def _build_bus(dut, cs: int) -> SpiBus:
    return SpiBus.from_entity(
        dut,
        sclk_name="spi_sclk",
        mosi_name="spi_mosi",
        miso_name="spi_miso",
        cs_name=f"cs_{cs}",
    )


async def _setup_env(dut, *, eeprom_id: bytes, card_id: bytes):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    eeprom = AT25010B_EEPROM(_build_bus(dut, 1))
    eeprom.load_memory(KEY_A, offset=0x00)
    eeprom.load_memory(eeprom_id, offset=0x40)

    def get_session_key_bytes() -> bytes:
        key_u128 = int(dut.layr.auth_i.auth_i.session_key.value)
        return key_u128.to_bytes(16, byteorder="big", signed=False)

    mfrc = LayrCardMock(
        _build_bus(dut, 0),
        key=KEY_A,
        card_id=card_id,
        get_session_key=get_session_key_bytes,
    )

    dut.spi_miso.value = 1
    dut.rst.value = 1
    for _ in range(50):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    return eeprom, mfrc


async def _run_until_decision(dut, *, timeout_cycles: int = 2_000_000):
    saw_busy = False
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if int(dut.status_busy.value):
            saw_busy = True
        if int(dut.status_unlock.value) or int(dut.status_fault.value):
            for _ in range(5):
                await RisingEdge(dut.clk)
            return saw_busy
    raise TimeoutError("Timed out waiting for unlock/fault decision")


@cocotb.test()
async def test_chip_e2e_unlock(dut):
    await _setup_env(dut, eeprom_id=CARD_ID, card_id=CARD_ID)
    saw_busy = await with_timeout(
        _run_until_decision(dut), timeout_time=150, timeout_unit="ms"
    )

    assert saw_busy, "Expected status_busy to assert during transaction"
    assert int(dut.status_unlock.value) == 1, "Expected unlock for valid card"
    assert int(dut.status_fault.value) == 0, "Did not expect fault for valid card"


@cocotb.test()
async def test_chip_e2e_fault(dut):
    wrong_id = CARD_ID[:-1] + b"\x00"
    await _setup_env(dut, eeprom_id=wrong_id, card_id=CARD_ID)
    saw_busy = await with_timeout(
        _run_until_decision(dut), timeout_time=150, timeout_unit="ms"
    )

    assert saw_busy, "Expected status_busy to assert during transaction"
    assert int(dut.status_fault.value) == 1, "Expected fault for invalid card"
    assert int(dut.status_unlock.value) == 0, "Did not expect unlock for invalid card"


def test_chip_controller_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent.parent
    chip = proj_path / "Chip" / "src"
    auth = proj_path / "Auth" / "src"
    aes = proj_path / "Auth" / "secworks-aes" / "src" / "rtl"
    layr = proj_path / "Layr" / "src"
    spi = proj_path / "SPI" / "src"

    sources = []
    for folder in [chip, auth, aes, layr, spi]:
        sources += [p for p in folder.rglob("*") if p.is_file()]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="chip",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
        verbose=True,
    )

    runner.test(hdl_toplevel="chip", test_module="test_chip", waves=True)


if __name__ == "__main__":
    test_chip_controller_runner()
