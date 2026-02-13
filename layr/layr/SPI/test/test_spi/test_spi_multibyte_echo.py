import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, with_timeout
import os
import sys
from cocotb_tools.runner import get_runner
from pathlib import Path

from cocotbext.spi import SpiSlaveBase, SpiConfig, SpiBus


class IncrementSpiSlave(SpiSlaveBase):
    """
    SPI slave that handles two multi-byte SS frames:
      1. TX frame: captures N bytes from MOSI
      2. RX frame: replies with each captured byte + 1

    Uses CPHA=0 in cocotbext-spi terms to match the spi_master RTL
    """

    def __init__(self, bus: SpiBus, num_bytes: int = 16):
        self._config = SpiConfig(
            word_width=8,
            cpol=False,
            cpha=False,
            msb_first=True,
            cs_active_low=True,
            frame_spacing_ns=1,
            data_output_idle=0,
        )
        self._num_bytes = num_bytes
        self.rx_bytes = []
        self._reply_bytes = []
        super().__init__(bus)

    # ------------------------------------------------------------------
    # CPHA=0 fix: pre-drive MISO before the first SCLK rising edge
    # ------------------------------------------------------------------
    # The cocotbext-spi SpiSlaveBase._shift() for CPHA=0 drives MISO on
    # the *falling* edge (second edge), meaning the very first rising edge
    # samples stale MISO data. In real SPI Mode 0 the slave must set up
    # the first data bit on MISO *before* the first SCLK rising edge
    # (typically on the CS falling edge).
    #
    # We fix this by pre-driving the MSB onto MISO before calling the
    # parent _shift(), and shifting the tx_word left by one position so
    # the parent's falling-edge drives produce bits [6:0] correctly.
    # The last falling-edge drive is a don't-care (next _shift will
    # override it, or CS will deassert).

    async def _shift(self, num_bits, tx_word=None):
        """Override _shift to pre-drive MSB on MISO for CPHA=0."""
        if not self._config.cpha and tx_word is not None and tx_word != 0:
            # Pre-drive the MSB onto MISO now (before first rising edge)
            msb = bool(tx_word & (1 << (num_bits - 1)))
            self._miso.value = int(msb)
            # Shift tx_word left by 1 so the parent's falling-edge drives
            # produce bits [n-2 : 0]. The parent will drive bit positions
            # (num_bits-1-k) from this shifted word:
            #   k=0 falling edge → shifted_word bit[n-1] = original bit[n-2]  ✓
            #   k=1 falling edge → shifted_word bit[n-2] = original bit[n-3]  ✓
            #   ...
            #   k=n-1 falling edge → shifted_word bit[0] = 0 (don't care)
            shifted_tx = (tx_word << 1) & ((1 << num_bits) - 1)
            return await super()._shift(num_bits, tx_word=shifted_tx)
        else:
            # tx_word is 0 or None — no data to send, use parent as-is
            return await super()._shift(num_bits, tx_word=tx_word)

    async def get_content(self):
        await self.idle.wait()
        return self.rx_bytes

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()

        if not self._reply_bytes:
            # First frame (TX): capture all bytes from master
            self.rx_bytes = []
            for _ in range(self._num_bytes):
                byte = int(await self._shift(8, tx_word=0x00))
                self.rx_bytes.append(byte)

            # Prepare reply: each byte incremented by 1 (wrapping at 0xFF)
            self._reply_bytes = [((b + 1) & 0xFF) for b in self.rx_bytes]
        else:
            # Second frame (RX): send back incremented bytes
            for i in range(self._num_bytes):
                await self._shift(8, tx_word=self._reply_bytes[i])

            # Reset for next test run
            self._reply_bytes = []

        await frame_end
        self.idle.set()


def _build_spi_bus(dut) -> SpiBus:
    return SpiBus.from_entity(dut, cs_name="ss")


@cocotb.test()
async def test_spi_multibyte_echo(dut):
    """
    Multi-byte echo test:
      1. Load 16 bytes into the TX buffer
      2. spi_multibyte_echo sends all 16 under one SS frame
      3. The IncrementSpiSlave captures them, adds 1 to each
      4. spi_multibyte_echo does a 2nd SS frame to read 16 bytes back
      5. We verify rx_buf[i] == tx_buf[i] + 1
    """
    NUM_BYTES = 16

    # 1. Clock
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # 2. Attach SPI slave
    spi_bus = _build_spi_bus(dut)
    spi_slave = IncrementSpiSlave(spi_bus, num_bytes=NUM_BYTES)

    # 3. Reset
    dut._log.info("Applying reset ...")
    dut.rst.value = 1
    dut.go.value = 0
    dut.rx_addr.value = 0
    dut.miso.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 5)

    # 4. TX payload is initialized in Verilog: tx_buf[i] = (i * 17 + 3) & 0xFF
    tx_payload = [(i + 10) & 0xFF for i in range(NUM_BYTES)]
    dut._log.info(f"TX payload (from Verilog): {[hex(b) for b in tx_payload]}")

    # 5. Start the multi-byte sequence
    dut._log.info("Starting multi-byte echo sequence ...")
    dut.go.value = 1
    await RisingEdge(dut.clk)
    dut.go.value = 0

    # 6. Wait for done
    for cycle in range(50000):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            break
    else:
        assert False, "Timed out waiting for done"

    dut._log.info(f"Sequence complete after ~{cycle} cycles")

    # 7. Verify what the slave received
    slave_rx = await with_timeout(spi_slave.get_content(), 10, "us")
    dut._log.info(f"Slave received:  {[hex(b) for b in slave_rx]}")

    assert slave_rx == tx_payload, (
        f"Slave MOSI mismatch:\n  got:      {[hex(b) for b in slave_rx]}\n"
        f"  expected: {[hex(b) for b in tx_payload]}"
    )

    # 8. Read back from RX buffer and verify increment
    expected_rx = [((b + 1) & 0xFF) for b in tx_payload]
    actual_rx = []
    for addr in range(NUM_BYTES):
        dut.rx_addr.value = addr
        await RisingEdge(dut.clk)
        # Allow one cycle for the combinational read to settle
        await RisingEdge(dut.clk)
        actual_rx.append(int(dut.rx_data.value))

    dut._log.info(f"RX buffer:       {[hex(b) for b in actual_rx]}")
    dut._log.info(f"Expected (TX+1): {[hex(b) for b in expected_rx]}")

    assert actual_rx == expected_rx, (
        f"RX mismatch:\n  got:      {[hex(b) for b in actual_rx]}\n"
        f"  expected: {[hex(b) for b in expected_rx]}"
    )

    await ClockCycles(dut.clk, 10)
    dut._log.info("test_spi_multibyte_echo PASSED ✓")


# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────


def test_spi_multibyte_echo_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI
    spi_ext_dir = str(test_dir.parent / "cocotbext-spi")

    src = proj_dir / "src"

    sources = [
        src / "spi_master.sv",
        test_dir / "spi_multibyte_echo.sv",
        test_dir / "test_spi_multibyte_echo_top.sv",
    ]

    extra_paths = [str(test_dir), spi_ext_dir]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        extra_paths.append(existing)
    os.environ["PYTHONPATH"] = os.pathsep.join(extra_paths)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_spi_multibyte_echo_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_spi_multibyte_echo_top",
        test_module="test_spi_multibyte_echo",
        waves=True,
    )


if __name__ == "__main__":
    test_spi_multibyte_echo_runner()
