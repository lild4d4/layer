"""Minimal debug test to trace where the FSM gets stuck."""
import os, sys
from pathlib import Path

_spi_ext = str(Path(__file__).resolve().parent.parent / "cocotbext-spi")
if _spi_ext not in sys.path:
    sys.path.insert(0, _spi_ext)

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner
from cocotbext.spi import SpiBus
from layr.layr.SPI.test.test_mrfc522.mock_mfrc522 import Mfrc522SpiSlave

os.environ["COCOTB_ANSI_OUTPUT"] = "1"

@cocotb.test()
async def test_debug_init(dut):
    """Probe internal signals to find where the init FSM gets stuck."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    dut.eeprom_cmd_valid.value = 0
    dut.eeprom_cmd_write.value = 0
    dut.eeprom_cmd_addr.value  = 0
    dut.eeprom_cmd_wdata.value = 0
    dut.nfc_cmd_valid.value = 0
    dut.nfc_cmd_write.value = 0
    dut.nfc_cmd_addr.value  = 0
    dut.nfc_cmd_wdata.value = 0

    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    spi_top = dut.u_spi_top
    axi_master = spi_top.u_axi_master
    pulp = spi_top.u_spi_master
    pulp_axi_if = pulp.u_axiregs

    for cycle in range(40):
        await RisingEdge(dut.clk)
        # Probe init FSM
        try:
            init_state = int(spi_top.init_state.value)
            init_done = int(spi_top.init_done.value)
            init_valid = int(spi_top.init_axi_req_valid.value)
        except Exception as e:
            init_state = f"ERR:{e}"
            init_done = "?"
            init_valid = "?"

        # Probe arbiter
        try:
            arb_valid = int(spi_top.arb_req_valid.value)
            arb_busy = int(spi_top.arb_busy.value)
            grant_active = int(spi_top.grant_active.value)
            grant_locked = int(spi_top.grant_locked.value)
        except Exception as e:
            arb_valid = f"ERR:{e}"
            arb_busy = "?"
            grant_active = "?"
            grant_locked = "?"

        # Probe AXI master
        try:
            axi_state = int(axi_master.state.value)
            axi_busy = int(axi_master.busy.value)
            axi_resp_done = int(axi_master.resp_done.value)
            axi_awvalid = int(axi_master.m_axi_awvalid.value)
            axi_awready = int(axi_master.m_axi_awready.value)
            axi_wvalid = int(axi_master.m_axi_wvalid.value)
            axi_wready = int(axi_master.m_axi_wready.value)
            axi_bvalid = int(axi_master.m_axi_bvalid.value)
            axi_bready = int(axi_master.m_axi_bready.value)
        except Exception as e:
            axi_state = f"ERR:{e}"
            axi_busy = "?"
            axi_resp_done = "?"
            axi_awvalid = "?"
            axi_awready = "?"
            axi_wvalid = "?"
            axi_wready = "?"
            axi_bvalid = "?"
            axi_bready = "?"

        # Probe PULP AXI IF write FSM
        try:
            pulp_aw_cs = int(pulp_axi_if.AW_CS.value)
            pulp_write_req = int(pulp_axi_if.write_req.value)
        except Exception as e:
            pulp_aw_cs = f"ERR:{e}"
            pulp_write_req = "?"

        dut._log.info(
            f"C{cycle:3d} | init_st={init_state} done={init_done} iv={init_valid} | "
            f"arb_v={arb_valid} arb_b={arb_busy} ga={grant_active} gl={grant_locked} | "
            f"axi_st={axi_state} busy={axi_busy} rd={axi_resp_done} "
            f"awv={axi_awvalid} awr={axi_awready} wv={axi_wvalid} wr={axi_wready} "
            f"bv={axi_bvalid} br={axi_bready} | "
            f"pulp_aw={pulp_aw_cs} wreq={pulp_write_req}"
        )

        if init_done == 1:
            dut._log.info("*** init_done is HIGH — init FSM completed! ***")
            break

    if init_done != 1:
        dut._log.error("*** init_done never went HIGH after 40 cycles! ***")
        assert False, "init_done stuck at 0"


@cocotb.test()
async def test_debug_nfc_write(dut):
    """Trace a full NFC write to find where the hang occurs."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    dut.eeprom_cmd_valid.value = 0
    dut.eeprom_cmd_write.value = 0
    dut.eeprom_cmd_addr.value  = 0
    dut.eeprom_cmd_wdata.value = 0
    dut.nfc_cmd_valid.value = 0
    dut.nfc_cmd_write.value = 0
    dut.nfc_cmd_addr.value  = 0
    dut.nfc_cmd_wdata.value = 0

    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    # Attach mock
    spi_bus = SpiBus(entity=dut, prefix="nfc", sclk_name="sclk",
                     mosi_name="mosi", miso_name="miso", cs_name="cs")
    mock = Mfrc522SpiSlave(spi_bus, version=0x92)

    # Wait for init_done
    spi_top = dut.u_spi_top
    for _ in range(50):
        await RisingEdge(dut.clk)
    init_done = int(spi_top.init_done.value)
    dut._log.info(f"init_done = {init_done}")
    assert init_done == 1, "init_done not high"

    # Issue NFC write: addr=0x14, data=0x55
    dut.nfc_cmd_addr.value  = 0x14
    dut.nfc_cmd_wdata.value = 0x55
    dut.nfc_cmd_write.value = 1
    dut.nfc_cmd_valid.value = 1
    await RisingEdge(dut.clk)
    dut.nfc_cmd_valid.value = 0

    nfc = spi_top.u_nfc
    axi_master = spi_top.u_axi_master

    # Trace for up to 2000 cycles (should be enough for one SPI transaction)
    for cycle in range(2000):
        await RisingEdge(dut.clk)

        try:
            nfc_state = int(nfc.state.value)
        except:
            nfc_state = "?"
        try:
            axi_st = int(axi_master.state.value)
            axi_busy = int(axi_master.busy.value)
            axi_rd = int(axi_master.resp_done.value)
        except:
            axi_st = "?"
            axi_busy = "?"
            axi_rd = "?"
        try:
            nfc_cs = int(dut.nfc_cs.value)
            nfc_sclk_val = int(dut.nfc_sclk.value)
        except:
            nfc_cs = "?"
            nfc_sclk_val = "?"
        try:
            cmd_done = int(dut.nfc_cmd_done.value)
            cmd_busy = int(dut.nfc_cmd_busy.value)
        except:
            cmd_done = "?"
            cmd_busy = "?"

        # Only log on state changes or every 50th cycle to reduce noise
        if cycle < 20 or cycle % 50 == 0 or cmd_done == 1:
            dut._log.info(
                f"C{cycle:4d} | nfc_st={nfc_state:2} axi_st={axi_st} "
                f"axi_busy={axi_busy} axi_rd={axi_rd} | "
                f"cs={nfc_cs} sclk={nfc_sclk_val} | "
                f"busy={cmd_busy} done={cmd_done}"
            )

        if cmd_done == 1:
            dut._log.info(f"*** nfc_cmd_done at cycle {cycle}! ***")
            break

    assert cmd_done == 1, f"nfc_cmd_done never fired after 2000 cycles, nfc_state={nfc_state}"


def test_debug_runner():
    sim = os.getenv("SIM", "icarus")

    test_dir = Path(__file__).resolve().parent
    proj_dir = test_dir.parent.parent  # layr/layr/SPI
    spi_ext_dir = str(test_dir.parent / "cocotbext-spi")

    src = proj_dir / "src"
    pulp = src / "axi_spi_master"

    sources = [
        pulp / "spi_master_clkgen.sv",
        pulp / "spi_master_tx.sv",
        pulp / "spi_master_rx.sv",
        pulp / "spi_master_fifo.sv",
        pulp / "spi_master_controller.sv",
        pulp / "spi_master_axi_if.sv",
        pulp / "axi_spi_master.sv",
        src / "axi_lite_master.sv",
        src / "nfc_spi.sv",
        src / "eeprom_spi.sv",
        src / "spi_init.sv",
        test_dir / "spi_top_wrapper.sv",
    ]

    extra_paths = [str(test_dir), spi_ext_dir]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        extra_paths.append(existing)
    os.environ["PYTHONPATH"] = os.pathsep.join(extra_paths)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="spi_top_wrapper",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )

    runner.test(
        hdl_toplevel="spi_top_wrapper",
        test_module="test_debug",
        waves=True,
    )

