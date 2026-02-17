from cocotb.triggers import RisingEdge, Timer, First
from cocotbext.spi import SpiBus

RESET_CYCLES = 50
TRANSACTION_TIMEOUT_US = 500


def build_spi_bus(dut, cs: int) -> SpiBus:
    """
    Build a SpiBus from the tb_top SPI port using custom signal names.

    The SpiBus.from_entity() method automatically finds signals by name,
    so we tell it the actual signal names used in eeprom_wire_modules.sv.
    """

    return SpiBus.from_entity(
        dut,
        sclk_name="spi_sclk",
        mosi_name="spi_mosi",
        miso_name="spi_miso",
        cs_name=f"cs_{cs}",
    )


async def reset_dut(dut):
    """Assert reset for RESET_CYCLES, then release and wait for init."""
    dut.rst.value = 1

    dut.spi_miso.value = 1

    dut.eeprom_start.value = 0
    dut.eeprom_get_key.value = 0

    dut.mfrc_cmd_init.value = 0
    dut.mfrc_cmd_poll.value = 0

    dut.mfrc_tx_valid.value = 0
    dut.mfrc_tx_len.value = 0
    dut.mfrc_tx_data.value = 0
    dut.mfrc_tx_last_bits.value = 0

    for _ in range(RESET_CYCLES):
        await RisingEdge(dut.clk)

    dut.rst.value = 0

    await RisingEdge(dut.clk)


async def wait_done(dut, wait_cond, timeout_us: int = TRANSACTION_TIMEOUT_US) -> None:
    """
    Block until wait_done pulses high, or raise TestFailure on timeout.
    """
    timeout_trigger = Timer(timeout_us, "us")
    done_trigger = RisingEdge(wait_cond)

    result = await First(done_trigger, timeout_trigger)
    if result is timeout_trigger:
        raise Exception(f"Timed out after {timeout_us} µs waiting for done. ")

    await RisingEdge(dut.clk)
