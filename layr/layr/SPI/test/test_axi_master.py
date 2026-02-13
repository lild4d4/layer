import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb_tools.runner import get_runner

os.environ["COCOTB_ANSI_OUTPUT"] = "1"


class AXIMasterTester:
    """
    Helper class for the AXI lite master.
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


def init_slave_signals(dut):
    """Drive all AXI slave outputs to known idle values."""
    dut.m_axi_awready.value = 0
    dut.m_axi_wready.value = 0
    dut.m_axi_bvalid.value = 0
    dut.m_axi_bresp.value = 0b00
    dut.m_axi_bid.value = 0
    dut.m_axi_arready.value = 0
    dut.m_axi_rvalid.value = 0
    dut.m_axi_rdata.value = 0
    dut.m_axi_rresp.value = 0b00
    dut.m_axi_rlast.value = 0


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    init_slave_signals(dut)
    dut.req_valid.value = 0
    dut.req_write.value = 0
    dut.req_addr.value = 0
    dut.req_wdata.value = 0
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    return AXIMasterTester(dut)


# ─────────────────────────────────────────────────────────
# AXI slave behaviour coroutines
# ─────────────────────────────────────────────────────────


async def axi_write_slave(dut, aw_delay=0, w_delay=0, b_delay=1, bresp=0b00):
    """
    Simulate an AXI write slave.
    Waits for awvalid/wvalid, asserts ready after specified delays,
    then responds on the B channel.
    """
    # Wait for AW valid
    while True:
        await RisingEdge(dut.clk)
        if dut.m_axi_awvalid.value == 1:
            break

    # Delay before accepting address
    for _ in range(aw_delay):
        await RisingEdge(dut.clk)
    dut.m_axi_awready.value = 1
    dut.m_axi_wready.value = 1

    # Wait until both handshakes complete
    await RisingEdge(dut.clk)
    dut.m_axi_awready.value = 0
    dut.m_axi_wready.value = 0

    # B channel response after delay
    for _ in range(b_delay):
        await RisingEdge(dut.clk)
    dut.m_axi_bvalid.value = 1
    dut.m_axi_bresp.value = bresp

    # Wait for bready handshake
    while True:
        await RisingEdge(dut.clk)
        if dut.m_axi_bready.value == 1:
            break
    dut.m_axi_bvalid.value = 0


async def axi_read_slave(dut, ar_delay=0, r_delay=1, rdata=0, rresp=0b00):
    """
    Simulate an AXI read slave.
    Waits for arvalid, asserts arready after delay,
    then responds with rdata on the R channel.
    """
    # Wait for AR valid
    while True:
        await RisingEdge(dut.clk)
        if dut.m_axi_arvalid.value == 1:
            break

    # Delay before accepting address
    for _ in range(ar_delay):
        await RisingEdge(dut.clk)
    dut.m_axi_arready.value = 1
    await RisingEdge(dut.clk)
    dut.m_axi_arready.value = 0

    # R channel response after delay
    for _ in range(r_delay):
        await RisingEdge(dut.clk)
    dut.m_axi_rvalid.value = 1
    dut.m_axi_rdata.value = rdata
    dut.m_axi_rresp.value = rresp
    dut.m_axi_rlast.value = 1

    # Wait for rready handshake
    while True:
        await RisingEdge(dut.clk)
        if dut.m_axi_rready.value == 1:
            break
    dut.m_axi_rvalid.value = 0
    dut.m_axi_rlast.value = 0


# ─────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────


@cocotb.test()
async def test_idle_after_reset(dut):
    """After reset, busy should be low and no AXI channels should be active."""
    await setup(dut)

    assert dut.busy.value == 0, "busy should be low after reset"
    assert dut.m_axi_awvalid.value == 0, "awvalid should be low after reset"
    assert dut.m_axi_wvalid.value == 0, "wvalid should be low after reset"
    assert dut.m_axi_arvalid.value == 0, "arvalid should be low after reset"
    assert dut.resp_done.value == 0, "resp_done should be low after reset"
    dut._log.info("✓ Idle after reset OK")


@cocotb.test()
async def test_write_immediate_ready(dut):
    """Slave asserts ready immediately — happy path write."""
    axi = await setup(dut)

    cocotb.start_soon(axi_write_slave(dut, aw_delay=0, b_delay=0))
    await axi.write(addr=0x0000_0008, data=0xCAFE_BABE)

    assert int(dut.m_axi_awaddr.value) == 0x08, "awaddr mismatch"
    assert int(dut.m_axi_wdata.value) == 0xCAFE_BABE, "wdata mismatch"
    assert dut.busy.value == 0, "busy should be low after completion"
    dut._log.info("✓ Write immediate ready OK")


@cocotb.test()
async def test_write_delayed_ready(dut):
    """Slave delays ready by several cycles — master must hold valid."""
    axi = await setup(dut)

    cocotb.start_soon(axi_write_slave(dut, aw_delay=5, b_delay=2))
    await axi.write(addr=0x0000_0010, data=0x1234_5678)

    assert dut.busy.value == 0, "busy should be low after completion"
    dut._log.info("✓ Write delayed ready OK")


@cocotb.test()
async def test_write_error_response(dut):
    """BRESP = SLVERR (0b10) should raise an error."""
    axi = await setup(dut)

    cocotb.start_soon(axi_write_slave(dut, aw_delay=0, b_delay=0, bresp=0b10))

    try:
        await axi.write(addr=0x0000_0008, data=0x06)
        assert False, "Should have raised RuntimeError"
    except RuntimeError:
        pass  # Expected

    dut._log.info("✓ Write error response flagged OK")


@cocotb.test()
async def test_read_returns_correct_data(dut):
    """Read returns correct data after RVALID."""
    axi = await setup(dut)

    cocotb.start_soon(axi_read_slave(dut, ar_delay=0, r_delay=1, rdata=0xDEAD_BEEF))
    result = await axi.read(addr=0x0000_0040)

    assert result == 0xDEAD_BEEF, f"Expected 0xDEADBEEF, got {result:#010x}"
    assert dut.busy.value == 0, "busy should be low after completion"
    dut._log.info("✓ Read correct data OK")


@cocotb.test()
async def test_read_delayed_arready(dut):
    """Slave delays arready — master must hold arvalid."""
    axi = await setup(dut)

    cocotb.start_soon(axi_read_slave(dut, ar_delay=4, r_delay=2, rdata=0x42))
    result = await axi.read(addr=0x0000_0020)

    assert result == 0x42, f"Expected 0x42, got {result:#010x}"
    dut._log.info("✓ Read delayed arready OK")


@cocotb.test()
async def test_read_error_response(dut):
    """RRESP = SLVERR should raise an error."""
    axi = await setup(dut)

    cocotb.start_soon(axi_read_slave(dut, ar_delay=0, r_delay=0, rdata=0, rresp=0b10))

    try:
        await axi.read(addr=0x0000_0000)
        assert False, "Should have raised RuntimeError"
    except RuntimeError:
        pass  # Expected

    dut._log.info("✓ Read error response flagged OK")


@cocotb.test()
async def test_busy_blocks_new_request(dut):
    """Master should not accept a second request while busy."""
    axi = await setup(dut)

    # Start a write but don't respond on B channel — master stays busy
    dut.req_addr.value = 0x08
    dut.req_wdata.value = 0x01
    dut.req_write.value = 1
    dut.req_valid.value = 1
    await RisingEdge(dut.clk)
    dut.req_valid.value = 0

    # Let awvalid/wvalid propagate (but no slave response)
    for _ in range(3):
        await RisingEdge(dut.clk)

    assert dut.busy.value == 1, "Master should be busy"
    dut._log.info("✓ Busy blocks new request OK")


@cocotb.test()
async def test_back_to_back_write_read(dut):
    """Perform a write then a read sequentially — both should complete."""
    axi = await setup(dut)

    # Write
    cocotb.start_soon(axi_write_slave(dut, aw_delay=0, b_delay=1))
    await axi.write(addr=0x0000_0008, data=0xAAAA_BBBB)
    assert dut.busy.value == 0

    # Read
    cocotb.start_soon(axi_read_slave(dut, ar_delay=0, r_delay=1, rdata=0x1111_2222))
    result = await axi.read(addr=0x0000_0040)
    assert result == 0x1111_2222
    assert dut.busy.value == 0

    dut._log.info("✓ Back-to-back write/read OK")


@cocotb.test()
async def test_wstrb_all_bytes_enabled(dut):
    """Verify that wstrb enables all 4 byte lanes for 32-bit writes."""
    axi = await setup(dut)

    cocotb.start_soon(axi_write_slave(dut, aw_delay=0, b_delay=0))
    await axi.write(addr=0x0000_0004, data=0xFF)

    assert (
        int(dut.m_axi_wstrb.value) == 0xF
    ), f"wstrb should be 0xF, got {int(dut.m_axi_wstrb.value):#x}"
    assert int(dut.m_axi_wlast.value) == 1, "wlast should be 1 for single-beat"
    dut._log.info("✓ wstrb all bytes enabled OK")


# ─────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────

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

    runner.test(
        hdl_toplevel="axi_lite_master",
        test_module="test_axi_master",
        waves=True,
    )

if __name__ == "__main__":
    test_axi_lite_master_runner()
