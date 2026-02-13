import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, with_timeout
import os
import sys
from cocotb_tools.runner import get_runner
from pathlib import Path

from cocotbext.spi import SpiSlaveBase, SpiConfig, SpiBus

class EchoSpiSlave(SpiSlaveBase):
    """
    SPI slave that captures the byte from the first transaction,
    then echoes it back during the second transaction.

    The spi_master RTL (CPOL=0) drives MOSI and raises sclk on the
    same posedge clk (state 1), then samples MISO and lowers sclk on
    the next posedge clk (state 2).

    From the slave's perspective we need CPHA=1 in cocotbext-spi terms:
      - 1st sclk edge (rising) → drive MISO
      - 2nd sclk edge (falling) → sample MOSI
    """

    def __init__(self, bus: SpiBus):
        self._config = SpiConfig(
            word_width=8,
            cpol=False,
            cpha=True,
            msb_first=True,
            cs_active_low=True,
            frame_spacing_ns=1,
            data_output_idle=0,
        )
        self.content = 0
        self._echo_byte = 0x00
        super().__init__(bus)

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
    return SpiBus.from_entity(dut, cs_name="ss")


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

    # 2. Attach SPI slave
    spi_bus = _build_spi_bus(dut)
    spi_slave = EchoSpiSlave(spi_bus)

    # 3. Reset (active-low)
    dut._log.info("Applying reset ...")
    dut.rst_n.value = 0
    dut.go.value = 0
    dut.tx_byte.value = 0
    dut.miso.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
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

        assert rx == test_data, (
            f"Echo mismatch: got {hex(rx)}, expected {hex(test_data)}"
        )

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
