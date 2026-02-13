import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import os
from cocotb_tools.runner import get_runner
from pathlib import Path

from cocotbext.spi import SpiSlaveBase, SpiConfig, SpiBus


class EchoSpiSlave(SpiSlaveBase):
    """
    SPI slave that captures the byte from the first transaction,
    then echoes it back during the second transaction.
    """

    def __init__(self, bus: SpiBus):
        self._config = SpiConfig(
            word_width=8,
            cpol=False,
            cpha=False,
            msb_first=True,
            cs_active_low=True,
            frame_spacing_ns=1,
            data_output_idle=0,
        )
        self.content = 0
        self._echo_byte = 0x00
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
        return self.content

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()

        # Full-duplex shift: receive MOSI, send _echo_byte on MISO
        self.content = int(await self._shift(8, tx_word=self._echo_byte))

        # After this transaction, store what we received so we echo
        # it back during the *next* transaction
        self._echo_byte = self.content

        await frame_end
        self.idle.set()


def _build_spi_bus(dut) -> SpiBus:
    return SpiBus.from_entity(
        dut,
        sclk_name="sclk",
        mosi_name="mosi",
        miso_name="miso",
        cs_name="ss",
    )


@cocotb.test()
async def test_spi_echo(dut):
    """
    End-to-end echo test:
      1. spi_echo sends tx_byte via spi_master  (1st SPI transaction)
      2. The EchoSpiSlave captures it
      3. spi_echo does a 2nd SPI transaction (dummy TX) to read back
      4. The slave replies with the captured byte
      5. We verify rx_byte == tx_byte
    """

    # 1. Clock
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # # 2. Attach SPI slave
    spi_bus = _build_spi_bus(dut)
    spi_slave = EchoSpiSlave(spi_bus)

    # 3. Reset (active-low)
    dut._log.info("Applying reset ...")
    dut.rst.value = 1
    dut.go.value = 0
    dut.tx_byte.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 5)

    for test_data in range(255):
        # 4. Start echo sequence
        dut._log.info(f"Starting echo sequence — TX: {hex(test_data)}")

        dut.tx_byte.value = test_data
        dut.go.value = 1
        await RisingEdge(dut.clk)
        dut.go.value = 0

        # 5. Wait for done
        for _ in range(5000):
            await RisingEdge(dut.clk)
            if dut.done.value == 1:
                break
        else:
            assert False, "Timed out waiting for done"

        # 6. Read rx_byte
        rx = int(dut.rx_byte.value)
        dut._log.info(f"Echoed rx_byte: {hex(rx)}")

        assert (
            rx == test_data
        ), f"Echo mismatch: got {hex(rx)}, expected {hex(test_data)}"

        await ClockCycles(dut.clk, 10)
    dut._log.info("test_spi_echo PASSED ✓")


# ─────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────


def test_spi_echo_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI
    spi_ext_dir = str(test_dir.parent / "cocotbext-spi")

    src = proj_dir / "src"

    sources = [
        src / "spi_master.sv",
        test_dir / "spi_echo.sv",
        test_dir / "test_spi_echo_top.sv",
    ]

    extra_paths = [str(test_dir), spi_ext_dir]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        extra_paths.append(existing)
    os.environ["PYTHONPATH"] = os.pathsep.join(extra_paths)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_spi_echo_top",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="test_spi_echo_top",
        test_module="test_spi_echo",
        waves=True,
    )


if __name__ == "__main__":
    test_spi_echo_runner()
