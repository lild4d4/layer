import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb_tools.runner import get_runner

os.environ["COCOTB_ANSI_OUTPUT"] = "1"


class AXIMasterTester:
    """
    Helper class for the AXI master
    """

    def __init__(self, dut) -> None:
        self.dut = dut

    async def write(self, addr: int, data: int, timeout_cycles=100):
        """
        Issue a write transaction and wait for done.
        """
        self.dut.req_addr.value = addr
        self.dut.req_wdata.value = data
        self.dut.req_write.value = 1
        self.dut.req_valid.value = 1

        await RisingEdge(self.dut.clk)
        self.dut.req_valid.value = 0

        # Wait for done pulse with timeout
        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.clk)
            if self.dut.resp_done.value == 1:
                if self.dut.resp_error.value == 1:
                    raise RuntimeError(f"AXI error on write {addr:#010x}")
                return

        raise TimeoutError(f"AXI write to {addr:#010x} timed out")

    async def read(self, addr: int, timeout_cycles: int = 100) -> int:
        """Issue a read transaction and return the data."""
        self.dut.req_addr.value = addr
        self.dut.req_write.value = 0
        self.dut.req_valid.value = 1

        await RisingEdge(self.dut.clk)
        self.dut.req_valid.value = 0

        for _ in range(timeout_cycles):
            await RisingEdge(self.dut.clk)
            if self.dut.resp_done.value == 1:
                if self.dut.resp_error.value == 1:
                    raise RuntimeError(f"AXI error on read from {addr:#010x}")
                return int(self.dut.resp_rdata.value)
        raise TimeoutError(f"AXI read from {addr:#010x} timed out")


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())  # type: ignore
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    return AXIMasterTester(dut)


@cocotb.test()
async def test_write_handshake_immediate_ready(dut):
    """Slave asserts ready immediately — happy path write."""
    axi = await setup(dut)

    # Simulate slave always ready
    dut.m_axi_awready.value = 1
    dut.m_axi_wready.value = 1
    dut.m_axi_bvalid.value = 0
    dut.m_axi_bresp.value = 0b00

    async def _respond_b_channel(dut, delay=1, resp=0b00):
        """Auto-respond on the B channel after a short delay."""
        for _ in range(delay):
            await RisingEdge(dut.clk)
        dut.m_axi_bvalid.value = 1
        dut.m_axi_bresp.value = resp
        await RisingEdge(dut.clk)
        dut.m_axi_bvalid.value = 0

    cocotb.start_soon(_respond_b_channel(dut))  # auto-respond

    await axi.write(addr=0x08, data=0x06)

    assert int(dut.m_axi_awaddr.value) == 0x08
    assert int(dut.m_axi_wdata.value) == 0x06


@cocotb.test()
async def test_write_handshake_delayed_ready(dut):
    """Slave delays ready by several cycles — shim must hold valid."""
    axi = await setup(dut)

    dut.m_axi_awready.value = 0
    dut.m_axi_wready.value = 0

    async def delayed_ready():
        for _ in range(5):
            await RisingEdge(dut.clk)
        dut.m_axi_awready.value = 1
        dut.m_axi_wready.value = 1
        await RisingEdge(dut.clk)
        dut.m_axi_bvalid.value = 1
        await RisingEdge(dut.clk)
        dut.m_axi_bvalid.value = 0

    cocotb.start_soon(delayed_ready())
    await axi.write(addr=0x08, data=0x06)


@cocotb.test()
async def test_read_handshake(dut):
    """Read returns correct data after RVALID."""
    axi = await setup(dut)

    dut.m_axi_arready.value = 0

    async def respond_read():
        await RisingEdge(dut.clk)
        dut.m_axi_arready.value = 1
        await RisingEdge(dut.clk)
        dut.m_axi_arready.value = 0
        dut.m_axi_rvalid.value = 1
        dut.m_axi_rdata.value = 0xDEADBEEF
        dut.m_axi_rresp.value = 0b00
        await RisingEdge(dut.clk)
        dut.m_axi_rvalid.value = 0

    cocotb.start_soon(respond_read())
    result = await axi.read(addr=0x20)

    assert result == 0xDEADBEEF, f"Expected 0xDEADBEEF, got {result:#010x}"


@cocotb.test()
async def test_error_response_flagged(dut):
    """BRESP != 00 should raise an error."""
    axi = await setup(dut)

    dut.m_axi_awready.value = 1
    dut.m_axi_wready.value = 1

    async def error_response():
        await RisingEdge(dut.clk)
        dut.m_axi_bvalid.value = 1
        dut.m_axi_bresp.value = 0b10  # SLVERR
        await RisingEdge(dut.clk)
        dut.m_axi_bvalid.value = 0

    cocotb.start_soon(error_response())

    try:
        await axi.write(addr=0x08, data=0x06)
        assert False, "Should have raised RuntimeError"
    except RuntimeError:
        pass  # Expected


@cocotb.test()
async def test_busy_blocks_new_request(dut):
    """Shim should not accept a second request while busy."""
    axi = await setup(dut)
    # Don't respond on B channel — shim stays busy
    dut.m_axi_awready.value = 1
    dut.m_axi_wready.value = 1
    dut.m_axi_bvalid.value = 0

    # First request — will stall waiting for bvalid
    cocotb.start_soon(axi.write(addr=0x08, data=0x01))
    await RisingEdge(dut.clk)

    # Busy should be high
    assert dut.busy.value == 1, "Shim should be busy"


def test_axi_lite_master_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent

    sources = [proj_path / "src" / "axi_lite_master.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="axi_lite_master",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    # runner.test(hdl_toplevel="axi_lite_master", test_module="test_axi_lite_master", waves=True)


if __name__ == "__main__":
    test_axi_lite_master_runner()
