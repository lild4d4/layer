from __future__ import annotations

from collections import deque
from typing import Deque, List, Optional, Sequence

import cocotb
from cocotb.triggers import Timer
from cocotbext.spi import SpiSlaveBase, SpiConfig


spi_config = SpiConfig(
    word_width=8,
    sclk_freq=25e6,
    cpol=False,
    cpha=False,
    msb_first=True,
    data_output_idle=1,
    frame_spacing_ns=1,
    ignore_rx_value=None,
    cs_active_low=True,
)


class Mfrc522SpiSlave(SpiSlaveBase):
    """
    MFRC522 SPI mock (register + FIFO + minimal command hooks).

    SPI protocol reminder:
      - First byte is address byte: bit7=R/W, bits6..1=addr, bit0 must be 0. :contentReference[oaicite:6]{index=6}
      - Write: addr, then data bytes. Read: addr, then dummy bytes while device outputs data. :contentReference[oaicite:7]{index=7}
    """

    # --- Register addresses (6-bit address space) ---
    REG_COMMAND      = 0x01  # CommandReg :contentReference[oaicite:8]{index=8}
    REG_COM_IRQ      = 0x04  # ComIrqReg :contentReference[oaicite:9]{index=9}
    REG_DIV_IRQ      = 0x05  # DivIrqReg :contentReference[oaicite:10]{index=10}
    REG_ERROR        = 0x06  # ErrorReg :contentReference[oaicite:11]{index=11}
    REG_STATUS1      = 0x07  # Status1Reg :contentReference[oaicite:12]{index=12}

    REG_FIFO_DATA    = 0x09  # FIFODataReg :contentReference[oaicite:13]{index=13}
    REG_FIFO_LEVEL   = 0x0A  # FIFOLevelReg :contentReference[oaicite:14]{index=14}
    REG_WATER_LEVEL  = 0x0B  # WaterLevelReg :contentReference[oaicite:15]{index=15}
    REG_BIT_FRAMING  = 0x0D  # BitFramingReg :contentReference[oaicite:16]{index=16}

    REG_VERSION      = 0x37  # VersionReg :contentReference[oaicite:17]{index=17}

    # --- Bits in ComIrqReg (bit7 is Set1: set/clear selection) ---
    COMIRQ_TIMER   = 1 << 0
    COMIRQ_ERR     = 1 << 1
    COMIRQ_LOALERT = 1 << 2
    COMIRQ_HIALERT = 1 << 3
    COMIRQ_IDLE    = 1 << 4
    COMIRQ_RX      = 1 << 5
    COMIRQ_TX      = 1 << 6
    COMIRQ_SET1    = 1 << 7  # :contentReference[oaicite:18]{index=18}

    # --- Bits in DivIrqReg (bit7 is Set2) ---
    DIVIRQ_CRCIRq  = 1 << 2
    DIVIRQ_SET2    = 1 << 7  # :contentReference[oaicite:19]{index=19}

    # --- Bits in Status1Reg ---
    STATUS1_LOALERT = 1 << 0
    STATUS1_HIALERT = 1 << 1
    STATUS1_IRQ     = 1 << 4
    STATUS1_CRCREADY= 1 << 5

    # --- Command codes (CommandReg.Command[3:0]) ---
    CMD_IDLE      = 0x00
    CMD_CALCCRC   = 0x03
    CMD_TRANSCEIVE= 0x0C
    CMD_SOFTRESET = 0x0F  # :contentReference[oaicite:20]{index=20}

    def __init__(self, bus, *, version: int = 0x92, uid: Sequence[int] = (0xDE, 0xAD, 0xBE, 0xEF),
                 config: Optional[SpiConfig] = None):
        self._config = config if config is not None else spi_config
        super().__init__(bus)

        self._regs: List[int] = [0x00] * 64
        self._fifo: Deque[int] = deque(maxlen=64)
        self._last_frame: List[int] = []

        self._uid = bytes(uid)
        self._version = version & 0xFF

        self._reset_regs()

    # -------------------------
    # Public helpers (optional)
    # -------------------------
    async def get_last_frame(self) -> List[int]:
        """Returns last MOSI frame bytes after slave goes idle."""
        await self.idle.wait()
        return list(self._last_frame)

    def preload_fifo(self, data: Sequence[int]) -> None:
        """Preload FIFO with bytes (useful for directed tests)."""
        for b in data:
            self._fifo_push(b & 0xFF)

    # -------------------------
    # Internal: register model
    # -------------------------
    def _reset_regs(self) -> None:
        # Minimal reset defaults we care about
        self._regs = [0x00] * 64
        self._fifo.clear()

        # CommandReg reset value is 0x20 (RcvOff=1 at reset). :contentReference[oaicite:21]{index=21}
        self._regs[self.REG_COMMAND] = 0x20

        # ComIrqReg reset value: 0x14. :contentReference[oaicite:22]{index=22}
        self._regs[self.REG_COM_IRQ] = 0x14 & 0x7F

        # ErrorReg reset value: 0x00. :contentReference[oaicite:23]{index=23}
        self._regs[self.REG_ERROR] = 0x00

        # Status1Reg reset value is 0x21, but we compute dynamics on read. :contentReference[oaicite:24]{index=24}
        self._regs[self.REG_STATUS1] = 0x21

        # FIFOLevel reset: 0x00; WaterLevel reset: 0x08. :contentReference[oaicite:25]{index=25}
        self._regs[self.REG_WATER_LEVEL] = 0x08

        # BitFramingReg reset (typical 0x00, ok for mock)
        self._regs[self.REG_BIT_FRAMING] = 0x00

        # VersionReg returns 0x91/0x92. :contentReference[oaicite:26]{index=26}
        self._regs[self.REG_VERSION] = self._version

        # DivIrqReg: dynamic; store only bits 0..6
        self._regs[self.REG_DIV_IRQ] = 0x00

        self._update_alerts_and_irq()

    def _update_alerts_and_irq(self) -> None:
        """
        Update HiAlert/LoAlert bits in Status1Reg and latched IRQ flags in ComIrqReg.
        Hi/Lo thresholds depend on WaterLevel and FIFO fill, and the FIFO is 64 bytes. 
        """
        water = self._regs[self.REG_WATER_LEVEL] & 0x3F
        flen = len(self._fifo)

        # From datasheet examples/equations: HiAlert when (64 - FIFOlen) <= WaterLevel; LoAlert when FIFOlen <= WaterLevel. 
        hialert = (64 - flen) <= water
        loalert = flen <= water

        # Status1Reg HiAlert/LoAlert are read-only dynamic bits. :contentReference[oaicite:29]{index=29}
        # We'll compute them on read, but also use them to latch ComIrqReg Hi/LoAlertIRq.
        if hialert:
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_HIALERT
        if loalert:
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_LOALERT

        # Status1Reg.IRq indicates "any enabled interrupt requests attention" (we don't model enables here),
        # but for a simple mock it’s useful to set IRq when any ComIrq/DivIrq bit is set. 
        any_irq = bool((self._regs[self.REG_COM_IRQ] & 0x7F) | (self._regs[self.REG_DIV_IRQ] & 0x7F))
        self._regs[self.REG_STATUS1] = (self._regs[self.REG_STATUS1] & ~self.STATUS1_IRQ) | (self.STATUS1_IRQ if any_irq else 0)

    def _fifo_push(self, b: int) -> None:
        if len(self._fifo) >= 64:
            # BufferOvfl is in ErrorReg and can only be cleared by FIFOLevelReg.FlushBuffer. 
            self._regs[self.REG_ERROR] |= (1 << 4)  # BufferOvfl
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_ERR
            return
        self._fifo.append(b & 0xFF)
        self._update_alerts_and_irq()

    def _fifo_pop(self) -> int:
        if not self._fifo:
            self._update_alerts_and_irq()
            return 0x00
        b = self._fifo.popleft()
        self._update_alerts_and_irq()
        return b

    def _read_reg(self, addr: int) -> int:
        addr &= 0x3F

        if addr == self.REG_FIFO_DATA:
            return self._fifo_pop()

        if addr == self.REG_FIFO_LEVEL:
            # bit7 FlushBuffer reads as 0; bits6..0 indicate FIFO length. 
            return len(self._fifo) & 0x7F

        if addr == self.REG_STATUS1:
            # Recompute Hi/LoAlert and IRq; CRCReady handled by stored bit. 
            water = self._regs[self.REG_WATER_LEVEL] & 0x3F
            flen = len(self._fifo)
            hialert = (64 - flen) <= water
            loalert = flen <= water

            v = self._regs[self.REG_STATUS1] & 0xFF
            v = (v & ~(self.STATUS1_HIALERT | self.STATUS1_LOALERT)) | \
                (self.STATUS1_HIALERT if hialert else 0) | \
                (self.STATUS1_LOALERT if loalert else 0)

            self._update_alerts_and_irq()
            return v

        if addr == self.REG_COM_IRQ:
            # bit7 Set1 is write-only; return only 0..6. :contentReference[oaicite:34]{index=34}
            return self._regs[addr] & 0x7F

        if addr == self.REG_DIV_IRQ:
            # bit7 Set2 is write-only; return only 0..6. :contentReference[oaicite:35]{index=35}
            return self._regs[addr] & 0x7F

        if addr == self.REG_VERSION:
            return self._regs[addr]

        return self._regs[addr] & 0xFF

    def _unread_reg(self, addr: int, value: int) -> None:
        """Undo a destructive _read_reg for FIFO registers.

        If a byte was pre-fetched from FIFODataReg to prepare MISO but
        the SPI frame ended before the master actually clocked it in,
        push the byte back to the front of the FIFO so it isn't lost.
        """
        addr &= 0x3F
        if addr == self.REG_FIFO_DATA:
            self._fifo.appendleft(value & 0xFF)
            self._update_alerts_and_irq()

    def _write_reg(self, addr: int, data: int) -> None:
        addr &= 0x3F
        data &= 0xFF

        if addr == self.REG_FIFO_DATA:
            self._fifo_push(data)
            return

        if addr == self.REG_FIFO_LEVEL:
            # Only FlushBuffer (bit7) is writable; reading it returns 0. 
            if data & 0x80:
                self._fifo.clear()
                # Clear BufferOvfl when flushing. 
                self._regs[self.REG_ERROR] &= ~(1 << 4)
                self._update_alerts_and_irq()
            return

        if addr == self.REG_WATER_LEVEL:
            self._regs[addr] = data & 0x3F
            self._update_alerts_and_irq()
            return

        if addr == self.REG_COM_IRQ:
            # Set1 controls set vs clear for marked bits. :contentReference[oaicite:38]{index=38}
            marked = data & 0x7F
            if data & self.COMIRQ_SET1:
                self._regs[addr] |= marked
            else:
                self._regs[addr] &= ~marked
            self._update_alerts_and_irq()
            return

        if addr == self.REG_DIV_IRQ:
            # Set2 controls set vs clear for marked bits. :contentReference[oaicite:39]{index=39}
            marked = data & 0x7F
            if data & self.DIVIRQ_SET2:
                self._regs[addr] |= marked
            else:
                self._regs[addr] &= ~marked
            self._update_alerts_and_irq()
            return

        if addr == self.REG_COMMAND:
            # CommandReg: writing command starts/stops; command may change dynamically. 
            self._regs[addr] = data
            cmd = data & 0x0F
            if cmd == self.CMD_SOFTRESET:
                self._reset_regs()
                # After reset, device goes idle-ish; also latch IdleIRq for convenience.
                self._regs[self.REG_COM_IRQ] |= self.COMIRQ_IDLE
                self._update_alerts_and_irq()
            elif cmd == self.CMD_CALCCRC:
                cocotb.start_soon(self._do_calccrc())
            # Transceive is actually kicked by BitFramingReg.StartSend; see _maybe_start_transceive().
            return

        if addr == self.REG_BIT_FRAMING:
            self._regs[addr] = data
            self._maybe_start_transceive()
            return

        if addr == self.REG_VERSION:
            # read-only in practice; ignore writes
            return

        # default: store
        self._regs[addr] = data
        self._update_alerts_and_irq()

    # -------------------------
    # Minimal command emulation
    # -------------------------
    def _maybe_start_transceive(self) -> None:
        cmd = self._regs[self.REG_COMMAND] & 0x0F
        start_send = bool(self._regs[self.REG_BIT_FRAMING] & 0x80)  # StartSend in BitFramingReg :contentReference[oaicite:41]{index=41}
        if cmd == self.CMD_TRANSCEIVE and start_send:
            cocotb.start_soon(self._do_transceive())

    async def _do_transceive(self) -> None:
        """
        Extremely simplified PICC emulation:
          - REQA (0x26) or WUPA (0x52) -> ATQA (0x04 0x00)
          - ANTICOLL CL1 (0x93 0x20) -> UID0..UID3 + BCC
        Then sets RxIRq + IdleIRq and clears StartSend.
        """
        # tiny delay to allow your DUT to finish register writes before polling IRQ
        await Timer(50, unit="ns")

        req = bytes(self._fifo)
        self._fifo.clear()

        resp: bytes = b""
        if req == b"\x26" or req == b"\x52":
            resp = b"\x04\x00"
        elif req == b"\x93\x20":
            uid = self._uid[:4]
            bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
            resp = uid + bytes([bcc])
        else:
            # default: no response
            resp = b""

        for b in resp:
            self._fifo_push(b)

        # Latch IRQ bits:
        self._regs[self.REG_COM_IRQ] |= (self.COMIRQ_RX | self.COMIRQ_IDLE)
        # Clear StartSend (in real chip it self-clears as state machine progresses)
        self._regs[self.REG_BIT_FRAMING] &= ~0x80

        self._update_alerts_and_irq()

    async def _do_calccrc(self) -> None:
        """
        Minimal CRC_A over FIFO content; sets DivIrqReg.CRCIRq and Status1Reg.CRCReady.
        CRC coprocessor indicates CRCReady and sets CRCIRq after processing FIFO data. 
        """
        await Timer(50, unit="ns")

        data = bytes(self._fifo)
        crc = self._crc_a(data)

        # We don't model the real CRCResult regs here; many drivers just wait on CRCIRq/CRCReady.
        self._regs[self.REG_DIV_IRQ] |= self.DIVIRQ_CRCIRq
        self._regs[self.REG_STATUS1] |= self.STATUS1_CRCREADY

        # Also set IdleIRq to indicate completion (handy for polling loops)
        self._regs[self.REG_COM_IRQ] |= self.COMIRQ_IDLE

        self._update_alerts_and_irq()

    @staticmethod
    def _crc_a(data: bytes) -> int:
        # ISO14443A CRC_A (preset 0x6363 is commonly used). :contentReference[oaicite:43]{index=43}
        crc = 0x6363
        for b in data:
            crc ^= b
            for _ in range(8):
                if crc & 0x0001:
                    crc = (crc >> 1) ^ 0x8408
                else:
                    crc >>= 1
        return crc & 0xFFFF

    # -------------------------
    # SPI transaction handling
    # -------------------------
    @staticmethod
    def _decode_addr_byte(addr_byte: int):
        """Decode MFRC522 SPI address byte.
        Format: bit7 = R/W (1=read, 0=write), bits[6:1] = register address, bit0 = 0.
        Returns (is_read, addr).
        """
        is_read = bool(addr_byte & 0x80)
        addr = (addr_byte >> 1) & 0x3F
        return is_read, addr

    @staticmethod
    def _looks_like_addr_byte_for_read(byte_val: int) -> bool:
        """Check if a byte looks like a valid MFRC522 read address byte.
        A read address byte has bit7=1 and bit0=0.
        """
        return (byte_val & 0x81) == 0x80

    async def _shift_byte_or_end(self, frame_end, tx: int) -> Optional[int]:
        """
        Shift one byte while watching for end-of-frame (CS deassert).
        Returns received byte, or None if frame ended before/at this byte.
        """
        from cocotb.triggers import RisingEdge, FallingEdge, First
        # Create a fresh frame_end trigger each call — cocotb 2.x triggers
        # may not be reusable after being cancelled by First().
        if self._config.cs_active_low:
            fe = RisingEdge(self._cs)
        else:
            fe = FallingEdge(self._cs)

        task = cocotb.start_soon(self._shift(8, tx_word=(tx & 0xFF)))
        done = await First(task, fe)
        if done is fe:
            task.cancel()
            return None
        rx = task.result()
        return int(rx) & 0xFF

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()
        self._last_frame = []

        # First byte: address byte. MISO during this byte is "X" (don't care).
        addr_byte = await self._shift_byte_or_end(frame_end, tx=0x00)
        if addr_byte is None:
            self.idle.set()
            return

        self._last_frame.append(addr_byte)
        is_read, addr = self._decode_addr_byte(addr_byte)

        if is_read:
            # Read transaction: for each byte the master clocks in,
            # we output the current register value on MISO.
            #
            # We must pre-read the register value before shifting
            # because MISO needs to be driven during the shift.
            # For destructive-read registers (FIFODataReg) this pops
            # a byte.  If the frame ends before the byte is actually
            # consumed by the master, we push it back via _unread_reg —
            # but only if the FIFO actually had content (otherwise
            # _fifo_pop returned 0x00 without popping, and pushing
            # back would insert a phantom byte).
            while True:
                fifo_len_before = len(self._fifo)
                tx = self._read_reg(addr)
                rx = await self._shift_byte_or_end(frame_end, tx=tx)
                if rx is None:
                    # Frame ended — the master never clocked this byte in.
                    # Undo the destructive read only if we actually popped.
                    if (addr & 0x3F) == self.REG_FIFO_DATA and len(self._fifo) < fifo_len_before:
                        self._unread_reg(addr, tx)
                    break
                self._last_frame.append(rx)

                # Accept "address-like" bytes mid-read to support
                # sequential register reads (addr changes mid-burst).
                if self._looks_like_addr_byte_for_read(rx):
                    _, addr = self._decode_addr_byte(rx)

        else:
            # Write: subsequent bytes are data for that address.
            while True:
                data = await self._shift_byte_or_end(frame_end, tx=0x00)
                if data is None:
                    break
                self._last_frame.append(data)
                self._write_reg(addr, data)

        # CS has already deasserted when _shift_byte_or_end returned None,
        # so do NOT await frame_end again — that would hang waiting for
        # the *next* rising edge of CS.
        self.idle.set()

