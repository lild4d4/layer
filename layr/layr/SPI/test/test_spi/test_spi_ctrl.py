import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, with_timeout
import os
import sys
from cocotb_tools.runner import get_runner
from pathlib import Path

# Make the local cocotbext-spi submodule importable
_spi_ext_path = str(Path(__file__).resolve().parent.parent / "cocotbext-spi")
if _spi_ext_path not in sys.path:
    sys.path.insert(0, _spi_ext_path)

from cocotbext.spi import SpiSlaveBase, SpiConfig, SpiBus


class SpiCtrlSlave(SpiSlaveBase):
    """
    Generic SPI slave for testing spi_ctrl.

    Within a single SS frame the master first writes w_len bytes,
    then reads r_len bytes.  From the slave's perspective this is
    one continuous transaction of (w_len + r_len) bytes.

    The slave captures the write bytes and replies with a configurable
    list of bytes during the read phase.
    """

    def __init__(self, bus: SpiBus, w_len: int, r_len: int,
                 reply_bytes: list[int] | None = None):
        self._config = SpiConfig(
            word_width=8,
            cpol=False,
            cpha=True,
            msb_first=True,
            cs_active_low=True,
            frame_spacing_ns=1,
            data_output_idle=0,
        )
        self._w_len = w_len
        self._r_len = r_len
        self._reply_bytes = reply_bytes or [0x00] * r_len
        self.rx_bytes: list[int] = []
        super().__init__(bus)

    async def get_content(self):
        await self.idle.wait()
        return self.rx_bytes

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()

        # Write phase: capture w_len bytes from MOSI (reply 0x00)
        self.rx_bytes = []
        for _ in range(self._w_len):
            byte = int(await self._shift(8, tx_word=0x00))
            self.rx_bytes.append(byte)

        # Read phase: send reply bytes on MISO (ignore MOSI)
        for i in range(self._r_len):
            await self._shift(8, tx_word=self._reply_bytes[i])

        await frame_end
        self.idle.set()


def _build_spi_bus(dut, cs_name: str) -> SpiBus:
    """Build a SpiBus using the specified CS signal (cs0 or cs1)."""
    return SpiBus.from_entity(dut, cs_name=cs_name)


def _bytes_to_int(byte_list: list[int]) -> int:
    """Pack a list of bytes into a 256-bit integer (byte 0 = MSB)."""
    val = 0
    for b in byte_list:
        val = (val << 8) | b
    # Left-align into 256 bits
    val <<= (32 - len(byte_list)) * 8
    return val


def _int_to_bytes(val: int, count: int) -> list[int]:
    """Extract count bytes from a 256-bit integer (byte 0 = MSB)."""
    result = []
    for i in range(count):
        shift = 255 - i * 8
        result.append((val >> (shift - 7)) & 0xFF)
    return result


async def _reset(dut):
    """Apply reset and initialise all inputs."""
    dut.rst_n.value = 0
    dut.go.value = 0
    dut.w_len.value = 0
    dut.r_len.value = 0
    dut.cs_sel.value = 0
    dut.tx_data.value = 0
    dut.miso.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def _start_and_wait(dut, tx_bytes: list[int], w_len: int, r_len: int,
                           cs_sel: int = 0):
    """Set tx_data, cs_sel, pulse go, and wait for done."""
    dut.tx_data.value = _bytes_to_int(tx_bytes) if tx_bytes else 0
    dut.w_len.value = w_len
    dut.r_len.value = r_len
    dut.cs_sel.value = cs_sel
    dut.go.value = 1
    await RisingEdge(dut.clk)
    dut.go.value = 0

    for _ in range(50000):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            return
    assert False, "Timed out waiting for done"


# ─────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_write_only_cs0(dut):
    """Pure write via cs0 (MFRC522): 4 bytes out, 0 bytes back."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)

    tx_payload = [0xDE, 0xAD, 0xBE, 0xEF]
    w_len = len(tx_payload)

    spi_bus = _build_spi_bus(dut, "cs0")
    slave = SpiCtrlSlave(spi_bus, w_len=w_len, r_len=0)

    await _start_and_wait(dut, tx_payload, w_len=w_len, r_len=0, cs_sel=0)

    slave_rx = await with_timeout(slave.get_content(), 10, "us")
    dut._log.info(f"Slave received: {[hex(b) for b in slave_rx]}")

    assert slave_rx == tx_payload, (
        f"Write mismatch:\n  got:      {[hex(b) for b in slave_rx]}\n"
        f"  expected: {[hex(b) for b in tx_payload]}"
    )
    # cs0 should have been asserted, cs1 should have stayed high the whole time
    assert dut.cs0.value == 1, "cs0 should be deasserted after transfer"
    assert dut.cs1.value == 1, "cs1 should never have been asserted"
    dut._log.info("test_write_only_cs0 PASSED ✓")


@cocotb.test()
async def test_write_only_cs1(dut):
    """Pure write via cs1 (EEPROM): 4 bytes out, 0 bytes back."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)

    tx_payload = [0xCA, 0xFE, 0xBA, 0xBE]
    w_len = len(tx_payload)

    spi_bus = _build_spi_bus(dut, "cs1")
    slave = SpiCtrlSlave(spi_bus, w_len=w_len, r_len=0)

    await _start_and_wait(dut, tx_payload, w_len=w_len, r_len=0, cs_sel=1)

    slave_rx = await with_timeout(slave.get_content(), 10, "us")
    dut._log.info(f"Slave received: {[hex(b) for b in slave_rx]}")

    assert slave_rx == tx_payload, (
        f"Write mismatch:\n  got:      {[hex(b) for b in slave_rx]}\n"
        f"  expected: {[hex(b) for b in tx_payload]}"
    )
    assert dut.cs0.value == 1, "cs0 should never have been asserted"
    assert dut.cs1.value == 1, "cs1 should be deasserted after transfer"
    dut._log.info("test_write_only_cs1 PASSED ✓")


@cocotb.test()
async def test_read_only(dut):
    """Pure read via cs0: 0 bytes out, 4 bytes back."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)

    reply = [0xCA, 0xFE, 0xBA, 0xBE]
    r_len = len(reply)

    spi_bus = _build_spi_bus(dut, "cs0")
    slave = SpiCtrlSlave(spi_bus, w_len=0, r_len=r_len, reply_bytes=reply)

    await _start_and_wait(dut, [], w_len=0, r_len=r_len, cs_sel=0)

    rx_val = int(dut.rx_data.value)
    actual = _int_to_bytes(rx_val, r_len)
    dut._log.info(f"RX data:    {[hex(b) for b in actual]}")
    dut._log.info(f"Expected:   {[hex(b) for b in reply]}")

    assert actual == reply, (
        f"Read mismatch:\n  got:      {[hex(b) for b in actual]}\n"
        f"  expected: {[hex(b) for b in reply]}"
    )
    dut._log.info("test_read_only PASSED ✓")


@cocotb.test()
async def test_write_then_read(dut):
    """Write 3 command bytes, read 8 data bytes — like a real peripheral."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)

    tx_payload = [0x03, 0x00, 0x10]  # e.g. READ cmd + 2-byte address
    w_len = len(tx_payload)
    reply = [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80]
    r_len = len(reply)

    spi_bus = _build_spi_bus(dut, "cs0")
    slave = SpiCtrlSlave(spi_bus, w_len=w_len, r_len=r_len, reply_bytes=reply)

    await _start_and_wait(dut, tx_payload, w_len=w_len, r_len=r_len, cs_sel=0)

    # Verify write phase
    slave_rx = await with_timeout(slave.get_content(), 10, "us")
    dut._log.info(f"Slave received (cmd): {[hex(b) for b in slave_rx]}")
    assert slave_rx == tx_payload, (
        f"Write mismatch:\n  got:      {[hex(b) for b in slave_rx]}\n"
        f"  expected: {[hex(b) for b in tx_payload]}"
    )

    # Verify read phase
    rx_val = int(dut.rx_data.value)
    actual = _int_to_bytes(rx_val, r_len)
    dut._log.info(f"RX data:    {[hex(b) for b in actual]}")
    dut._log.info(f"Expected:   {[hex(b) for b in reply]}")
    assert actual == reply, (
        f"Read mismatch:\n  got:      {[hex(b) for b in actual]}\n"
        f"  expected: {[hex(b) for b in reply]}"
    )
    dut._log.info("test_write_then_read PASSED ✓")


@cocotb.test()
async def test_max_32_bytes(dut):
    """Full 32-byte write + 32-byte read via cs1."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)

    tx_payload = [(i * 7 + 1) & 0xFF for i in range(32)]
    w_len = 32
    reply = [((b + 1) & 0xFF) for b in tx_payload]
    r_len = 32

    spi_bus = _build_spi_bus(dut, "cs1")
    slave = SpiCtrlSlave(spi_bus, w_len=w_len, r_len=r_len, reply_bytes=reply)

    await _start_and_wait(dut, tx_payload, w_len=w_len, r_len=r_len, cs_sel=1)

    # Verify write
    slave_rx = await with_timeout(slave.get_content(), 10, "us")
    dut._log.info(f"Slave received {len(slave_rx)} bytes")
    assert slave_rx == tx_payload

    # Verify read
    rx_val = int(dut.rx_data.value)
    actual = _int_to_bytes(rx_val, r_len)
    dut._log.info(f"RX data {len(actual)} bytes")
    assert actual == reply, (
        f"Read mismatch at 32 bytes:\n  got:      {[hex(b) for b in actual]}\n"
        f"  expected: {[hex(b) for b in reply]}"
    )
    dut._log.info("test_max_32_bytes PASSED ✓")


@cocotb.test()
async def test_cs_isolation(dut):
    """
    Verify that selecting cs0 does not affect cs1 and vice versa.
    Run two back-to-back transactions on different chip selects.
    """
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)

    # ── Transaction 1: write to cs0 (MFRC522) ──
    tx1 = [0xAA, 0xBB]
    spi_bus0 = _build_spi_bus(dut, "cs0")
    slave0 = SpiCtrlSlave(spi_bus0, w_len=2, r_len=0)

    await _start_and_wait(dut, tx1, w_len=2, r_len=0, cs_sel=0)
    slave0_rx = await with_timeout(slave0.get_content(), 10, "us")
    dut._log.info(f"CS0 slave received: {[hex(b) for b in slave0_rx]}")
    assert slave0_rx == tx1

    await ClockCycles(dut.clk, 5)

    # ── Transaction 2: write to cs1 (EEPROM) ──
    tx2 = [0xCC, 0xDD]
    spi_bus1 = _build_spi_bus(dut, "cs1")
    slave1 = SpiCtrlSlave(spi_bus1, w_len=2, r_len=0)

    await _start_and_wait(dut, tx2, w_len=2, r_len=0, cs_sel=1)
    slave1_rx = await with_timeout(slave1.get_content(), 10, "us")
    dut._log.info(f"CS1 slave received: {[hex(b) for b in slave1_rx]}")
    assert slave1_rx == tx2

    dut._log.info("test_cs_isolation PASSED ✓")


# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────

def test_spi_ctrl_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI
    spi_ext_dir = str(test_dir.parent / "cocotbext-spi")

    src = proj_dir / "src"

    sources = [
        src / "spi_master.sv",
        src / "spi_ctrl.sv",
        test_dir / "test_spi_ctrl_top.sv",
    ]

    extra_paths = [str(test_dir), spi_ext_dir]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        extra_paths.append(existing)
    os.environ["PYTHONPATH"] = os.pathsep.join(extra_paths)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_spi_ctrl_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_spi_ctrl_top",
        test_module="test_spi_ctrl",
        waves=True,
    )


if __name__ == "__main__":
    test_spi_ctrl_runner()
