from __future__ import annotations

from collections import deque
from typing import Deque, List, Optional, Sequence

import cocotb
from cocotb.triggers import Timer
from cocotbext.spi import SpiSlaveBase, SpiConfig


class Mfrc522SpiSlave(SpiSlaveBase):
    """
    MFRC522 SPI mock (register + FIFO + minimal command hooks).

    SPI protocol reminder:
      - First byte is address byte: bit7=R/W, bits6..1=addr, bit0 must be 0. :contentReference[oaicite:6]{index=6}
      - Write: addr, then data bytes. Read: addr, then dummy bytes while device outputs data. :contentReference[oaicite:7]{index=7}
    """

    # --- Register addresses (6-bit address space) ---
    REG_COMMAND      = 0x01  # CommandReg
    REG_COM_IEN      = 0x02  # ComIEnReg
    REG_DIV_IEN      = 0x03  # DivIEnReg
    REG_COM_IRQ      = 0x04  # ComIrqReg
    REG_DIV_IRQ      = 0x05  # DivIrqReg
    REG_ERROR        = 0x06  # ErrorReg
    REG_STATUS1      = 0x07  # Status1Reg

    REG_FIFO_DATA    = 0x09  # FIFODataReg
    REG_FIFO_LEVEL   = 0x0A  # FIFOLevelReg
    REG_WATER_LEVEL  = 0x0B  # WaterLevelReg
    REG_CONTROL      = 0x0C  # ControlReg
    REG_BIT_FRAMING  = 0x0D  # BitFramingReg

    REG_MODE         = 0x11  # ModeReg
    REG_CRC_RESULT_MSB = 0x21  # CRCResultReg (higher bits)
    REG_CRC_RESULT_LSB = 0x22  # CRCResultReg (lower bits)

    REG_VERSION      = 0x37  # VersionReg
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
    DIVIRQ_MFINACT = 1 << 4
    DIVIRQ_CRCIRq  = 1 << 2
    DIVIRQ_SET2    = 1 << 7

    # --- Bits in ErrorReg ---
    ERR_PROTOCOL    = 1 << 0
    ERR_PARITY      = 1 << 1
    ERR_CRC         = 1 << 2
    ERR_COLLISION   = 1 << 3
    ERR_BUFFER_OVFL = 1 << 4
    ERR_TEMPCOL     = 1 << 5  # reserved/implementation-specific
    ERR_TEMP_ERR    = 1 << 6
    ERR_WR_ERR      = 1 << 7

    # --- Bits in Status1Reg ---
    STATUS1_LOALERT  = 1 << 0
    STATUS1_HIALERT  = 1 << 1
    STATUS1_TRUNNING = 1 << 3
    STATUS1_IRQ      = 1 << 4
    STATUS1_CRCREADY = 1 << 5
    STATUS1_CRCOK    = 1 << 6


    # --- Command codes (CommandReg.Command[3:0]) ---
    CMD_IDLE      = 0x00
    CMD_CALCCRC   = 0x03
    CMD_NO_CMD_CHANGE = 0x07
    CMD_TRANSCEIVE= 0x0C
    CMD_SOFTRESET = 0x0F  # :contentReference[oaicite:20]{index=20}

    def __init__(self, bus):
        self._config = SpiConfig(
            word_width=8,
            cpol=False,
            cpha=False,
            msb_first=True,
            cs_active_low=True,
            frame_spacing_ns=1,
            data_output_idle=1,
        )
        super().__init__(bus)

        self._regs: List[int] = [0x00] * 64
        self._fifo: Deque[int] = deque(maxlen=64)
        self._last_frame: List[int] = []

        self._uid = bytes((0xDE, 0xAD, 0xBE, 0xEF))
        self._version = 0x92

        # ── Test-injectable overrides ──
        # If set, _do_transceive will OR this value into ErrorReg
        # after processing the command, regardless of the response.
        self._inject_error: int = 0x00

        # Track FIFO alert level transitions for edge-latched Hi/LoAlertIRq
        self._prev_hialert: bool = False
        self._prev_loalert: bool = False

        self._reset_regs()

    # -------------------------
    # SPI address helpers
    # -------------------------
    @staticmethod
    def _decode_addr_byte(addr_byte: int) -> tuple[bool, int]:
        """Decode MFRC522 SPI address byte.

        Format (datasheet):
          - bit7: R/W (1=read, 0=write)
          - bits[6:1]: register address
          - bit0: must be 0

        Returns (is_read, addr).
        """
        is_read = bool(addr_byte & 0x80)
        addr = (addr_byte >> 1) & 0x3F
        return is_read, addr

    @staticmethod
    def _looks_like_addr_byte_for_read(byte_val: int) -> bool:
        """Heuristic: does this byte look like a valid *read* address byte?

        A read address byte has bit7=1 and bit0=0.
        """
        return (byte_val & 0x81) == 0x80
    # ------------------------------------------------------------------
    # CPHA=0 fix: pre-drive MISO before the first SCLK rising edge
    # ------------------------------------------------------------------
    async def _shift(self, num_bits, tx_word=None):
        """Override _shift to pre-drive MSB on MISO for CPHA=0.

        For CPHA=0 the first data bit must be valid before the first rising edge.
        SpiSlaveBase normally drives the first bit on the first falling edge, so we
        pre-drive it here unconditionally (even if the MSB is 0).
        """
        if not self._config.cpha and tx_word is not None:
            msb = bool(tx_word & (1 << (num_bits - 1)))
            self._miso.value = int(msb)
            shifted_tx = (tx_word << 1) & ((1 << num_bits) - 1)
            return await super()._shift(num_bits, tx_word=shifted_tx)
        return await super()._shift(num_bits, tx_word=tx_word)


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

        # CommandReg reset value is 0x20 (RcvOff=1 at reset).
        self._regs[self.REG_COMMAND] = 0x20

        # Interrupt enable registers
        self._regs[self.REG_COM_IEN] = 0x80  # IRqInv=1, all enables cleared
        self._regs[self.REG_DIV_IEN] = 0x00

        # IRQ and status registers
        self._regs[self.REG_COM_IRQ] = 0x14 & 0x7F  # IdleIRq + LoAlertIRq at reset
        self._regs[self.REG_DIV_IRQ] = 0x00
        self._regs[self.REG_ERROR] = 0x00
        self._regs[self.REG_STATUS1] = 0x21  # CRCReady=1, LoAlert=1 at reset

        # FIFO / framing
        self._regs[self.REG_WATER_LEVEL] = 0x08
        self._regs[self.REG_CONTROL] = 0x10
        self._regs[self.REG_BIT_FRAMING] = 0x00

        # CRC / mode
        self._regs[self.REG_MODE] = 0x3F
        self._regs[self.REG_CRC_RESULT_MSB] = 0xFF
        self._regs[self.REG_CRC_RESULT_LSB] = 0xFF

        # VersionReg returns 0x91/0x92.
        self._regs[self.REG_VERSION] = self._version

        # Initialize FIFO alert edge trackers to the post-reset level state.
        hialert, loalert = self._compute_alerts()
        self._prev_hialert = hialert
        self._prev_loalert = loalert

        self._update_alerts_and_irq()
    def _compute_alerts(self) -> tuple[bool, bool]:
        """Compute current HiAlert/LoAlert level bits from FIFO fill and WaterLevel."""
        water = self._regs[self.REG_WATER_LEVEL] & 0x3F
        flen = len(self._fifo)

        # HiAlert when (64 - FIFOlen) <= WaterLevel; LoAlert when FIFOlen <= WaterLevel.
        hialert = (64 - flen) <= water
        loalert = flen <= water
        return hialert, loalert

    def _update_status1_irq(self) -> None:
        """Update Status1Reg.IRq based on *enabled* pending interrupt sources."""
        com_en = self._regs[self.REG_COM_IEN] & 0x7F
        div_en = self._regs[self.REG_DIV_IEN] & (self.DIVIRQ_MFINACT | self.DIVIRQ_CRCIRq)

        com_pending = (self._regs[self.REG_COM_IRQ] & 0x7F) & com_en
        div_pending = (self._regs[self.REG_DIV_IRQ] & 0x7F) & div_en

        any_irq = bool(com_pending | div_pending)
        if any_irq:
            self._regs[self.REG_STATUS1] |= self.STATUS1_IRQ
        else:
            self._regs[self.REG_STATUS1] &= ~self.STATUS1_IRQ

    def _update_alerts_and_irq(self) -> None:
        """Update Status1Reg Hi/LoAlert bits and edge-latch Hi/LoAlertIRq in ComIrqReg."""
        hialert, loalert = self._compute_alerts()

        # Status1Reg HiAlert/LoAlert are read-only dynamic bits; keep them in the shadow reg.
        s1 = self._regs[self.REG_STATUS1]
        s1 &= ~(self.STATUS1_HIALERT | self.STATUS1_LOALERT)
        if hialert:
            s1 |= self.STATUS1_HIALERT
        if loalert:
            s1 |= self.STATUS1_LOALERT
        self._regs[self.REG_STATUS1] = s1

        # Hi/LoAlertIRq are edge-latched (store the event) and cleared only by SW via Set1.
        if hialert and not self._prev_hialert:
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_HIALERT
        if loalert and not self._prev_loalert:
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_LOALERT
        self._prev_hialert = hialert
        self._prev_loalert = loalert

        # ErrIRq is set when any error bit in ErrorReg is set (and stays set until SW clears it).
        if self._regs[self.REG_ERROR] != 0:
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_ERR

        self._update_status1_irq()



    def _fifo_push(self, b: int) -> None:
        if len(self._fifo) >= 64:
            # BufferOvfl is in ErrorReg and can only be cleared by FIFOLevelReg.FlushBuffer. 
            self._regs[self.REG_ERROR] |= self.ERR_BUFFER_OVFL  # BufferOvfl
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
            # Keep Hi/LoAlert and IRq up to date before exposing the shadow value.
            self._update_alerts_and_irq()
            return self._regs[addr] & 0x7B  # mask reserved bits (7 and 2)

        if addr == self.REG_COM_IRQ:
            # bit7 Set1 is write-only; return only 0..6.
            return self._regs[addr] & 0x7F

        if addr == self.REG_DIV_IRQ:
            # bit7 Set2 is write-only; return only 0..6.
            return self._regs[addr] & 0x7F

        if addr == self.REG_BIT_FRAMING:
            # bit7 StartSend is write-only (reads as 0).
            return self._regs[addr] & 0x7F

        if addr == self.REG_CONTROL:
            # bits7..6 are write-only (read as 0).
            return self._regs[addr] & 0x3F

        if addr == self.REG_WATER_LEVEL:
            return self._regs[addr] & 0x3F

        if addr in (self.REG_CRC_RESULT_MSB, self.REG_CRC_RESULT_LSB):
            return self._regs[addr] & 0xFF

        if addr == self.REG_VERSION:
            return self._regs[addr] & 0xFF

        return self._regs[addr] & 0xFF
    
    def _unread_reg(self, addr: int, value: int) -> None:
        """Undo a destructive _read_reg for FIFO registers.

        If a byte was pre-fetched from FIFODataReg to prepare MISO but the SPI
        frame ended before the master actually clocked it in, push the byte back
        to the front of the FIFO so it isn't lost.
        """
        addr &= 0x3F
        if addr == self.REG_FIFO_DATA:
            self._fifo.appendleft(value & 0xFF)
            self._update_alerts_and_irq()

    def _write_reg(self, addr: int, data: int) -> None:
        addr &= 0x3F
        data &= 0xFF

        # Ignore writes to read-only regs we currently shadow.
        if addr in (self.REG_STATUS1, self.REG_ERROR, self.REG_CONTROL, self.REG_CRC_RESULT_MSB, self.REG_CRC_RESULT_LSB, self.REG_VERSION):
            return

        if addr == self.REG_COMMAND:
            cmd = data & 0x0F

            # Command execution clears all error bits except TempErr. BufferOvfl is
            # only cleared by FlushBuffer, so preserve it as well.
            if cmd not in (self.CMD_IDLE, getattr(self, "CMD_NO_CMD_CHANGE", 0x07)):
                preserve = self._regs[self.REG_ERROR] & (self.ERR_TEMP_ERR | self.ERR_BUFFER_OVFL)
                self._regs[self.REG_ERROR] = preserve

            self._regs[addr] = data

            if cmd == self.CMD_SOFTRESET:
                self._reset_regs()
                return
            if cmd == self.CMD_CALCCRC:
                cocotb.start_soon(self._do_calccrc())
            if cmd == self.CMD_TRANSCEIVE:
                self._maybe_start_transceive()
            self._update_alerts_and_irq()
            return

        if addr == self.REG_COM_IEN:
            self._regs[addr] = data
            self._update_status1_irq()
            return

        if addr == self.REG_DIV_IEN:
            self._regs[addr] = data & (0x80 | 0x10 | 0x04)  # IRQPushPull, MfinActIEn, CRCIEn
            self._update_status1_irq()
            return

        if addr == self.REG_MODE:
            # mask reserved bits (6,4,2)
            self._regs[addr] = data & (0x80 | 0x20 | 0x08 | 0x03)
            return

        if addr == self.REG_FIFO_DATA:
            self._fifo_push(data)
            return

        if addr == self.REG_FIFO_LEVEL:
            # Bit7 (FlushBuffer) is W: if set, clears FIFO and also clears BufferOvfl in ErrorReg.
            if data & 0x80:
                self._fifo.clear()
                self._regs[self.REG_ERROR] &= ~self.ERR_BUFFER_OVFL
            # Lower bits are read-only FIFO level.
            self._update_alerts_and_irq()
            return

        if addr == self.REG_WATER_LEVEL:
            self._regs[addr] = data & 0x3F
            self._update_alerts_and_irq()
            return

        if addr == self.REG_BIT_FRAMING:
            # Bit7 StartSend is write-only trigger; we keep a shadow but reads mask it out.
            self._regs[addr] = data
            self._maybe_start_transceive()
            return

        if addr == self.REG_COM_IRQ:
            # Set1 semantics: if bit7=1, set marked bits; if bit7=0, clear marked bits.
            marked = data & 0x7F
            if data & self.COMIRQ_SET1:
                self._regs[addr] |= marked
            else:
                self._regs[addr] &= ~marked
            self._update_status1_irq()
            return

        if addr == self.REG_DIV_IRQ:
            marked = data & 0x7F
            if data & self.DIVIRQ_SET2:
                self._regs[addr] |= marked
            else:
                self._regs[addr] &= ~marked
            self._update_status1_irq()
            return

        # Default: store
        self._regs[addr] = data


    def _maybe_start_transceive(self) -> None:
        cmd = self._regs[self.REG_COMMAND] & 0x0F
        start_send = bool(self._regs[self.REG_BIT_FRAMING] & 0x80)  # StartSend in BitFramingReg :contentReference[oaicite:41]{index=41}
        if cmd == self.CMD_TRANSCEIVE and start_send:
            cocotb.start_soon(self._do_transceive())


    async def _do_transceive(self) -> None:
        """Very small ISO/IEC 14443-A PICC emulation for bring-up.

        Supports:
          - REQA (0x26) / WUPA (0x52) -> ATQA (0x04 0x00)
          - ANTICOLL CL1 (0x93 0x20) -> UID0..UID3 + BCC
          - SELECT   CL1 (0x93 0x70 + UID0..UID3 + BCC + CRC_A) -> SAK + CRC_A
        """
        await Timer(50, unit="ns")

        req = bytes(self._fifo)
        self._fifo.clear()

        resp: bytes = b""
        rx_last_bits: int = 0   # ControlReg[2:0]

        if req in (b"\x26", b"\x52"):
            resp = b"\x04\x00"

        elif req == b"\x93\x20":
            uid = self._uid[:4]
            bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
            resp = uid + bytes([bcc])

        elif len(req) in (7, 9) and req[0] == 0x93 and req[1] == 0x70:
            uid = self._uid[:4]
            uid_in = req[2:6]
            bcc_in = req[6]
            bcc_ok = (bcc_in == (uid_in[0] ^ uid_in[1] ^ uid_in[2] ^ uid_in[3]))
            uid_ok = (uid_in == uid)

            if uid_ok and bcc_ok:
                sak = 0x08
                crc = self._crc_a(bytes([sak]))
                # CRC_A is transmitted LSB first.
                resp = bytes([sak, crc & 0xFF, (crc >> 8) & 0xFF])
            else:
                # Protocol error: no response. The real chip would time out / set TimerIRq.
                self._regs[self.REG_ERROR] |= self.ERR_PROTOCOL

        # Enqueue response into FIFO
        for b in resp:
            self._fifo_push(b)

        # Update ControlReg RxLastBits (bits 2:0)
        self._regs[self.REG_CONTROL] = (self._regs[self.REG_CONTROL] & 0xF8) | (rx_last_bits & 0x07)

        # IRQs: set RxIRq only when we actually have a response.
        if resp:
            self._regs[self.REG_COM_IRQ] |= (self.COMIRQ_RX | self.COMIRQ_IDLE)
        else:
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_IDLE

        # Optional error injection hook for tests.
        if self._inject_error:
            self._regs[self.REG_ERROR] |= self._inject_error
            self._regs[self.REG_COM_IRQ] |= (self.COMIRQ_RX | self.COMIRQ_IDLE)

        # Clear StartSend (self-clears in silicon as the state machine progresses)
        self._regs[self.REG_BIT_FRAMING] &= ~0x80

        self._update_alerts_and_irq()

    async def _do_calccrc(self) -> None:
        """Emulate MFRC522 CalcCRC command over FIFO content."""
        # During calculation, CRCReady and CRCOk go low.
        self._regs[self.REG_STATUS1] &= ~(self.STATUS1_CRCREADY | self.STATUS1_CRCOK)
        self._update_status1_irq()

        await Timer(50, unit="ns")

        data = bytes(self._fifo)

        mode = self._regs[self.REG_MODE]
        preset_sel = mode & 0x03
        preset = {
            0: 0x0000,  # 0000b
            1: 0x6363,  # 0001b (ISO 14443-A)
            2: 0xA671,  # 0010b
            3: 0xFFFF,  # 0011b
        }[preset_sel]

        crc = self._crc16(data, preset)

        msb = (crc >> 8) & 0xFF
        lsb = crc & 0xFF

        # If MSBFirst is set, CRCResult register values are bit-reversed.
        if mode & 0x80:
            msb = self._bit_reverse8(msb)
            lsb = self._bit_reverse8(lsb)

        self._regs[self.REG_CRC_RESULT_MSB] = msb
        self._regs[self.REG_CRC_RESULT_LSB] = lsb

        self._regs[self.REG_DIV_IRQ] |= self.DIVIRQ_CRCIRq
        self._regs[self.REG_STATUS1] |= self.STATUS1_CRCREADY
        if crc == 0:
            self._regs[self.REG_STATUS1] |= self.STATUS1_CRCOK

        # CalcCRC terminates and returns to Idle -> IdleIRq set.
        self._regs[self.REG_COM_IRQ] |= self.COMIRQ_IDLE

        self._update_alerts_and_irq()

    @staticmethod
    def _bit_reverse8(x: int) -> int:
        x &= 0xFF
        x = ((x & 0xF0) >> 4) | ((x & 0x0F) << 4)
        x = ((x & 0xCC) >> 2) | ((x & 0x33) << 2)
        x = ((x & 0xAA) >> 1) | ((x & 0x55) << 1)
        return x

    @staticmethod
    def _crc16(data: bytes, preset: int) -> int:
        """CRC coprocessor model (poly x^16 + x^12 + x^5 + 1, LSB-first)."""
        crc = preset & 0xFFFF
        for b in data:
            crc ^= b
            for _ in range(8):
                if crc & 0x0001:
                    crc = (crc >> 1) ^ 0x8408
                else:
                    crc >>= 1
        return crc & 0xFFFF

    @classmethod
    def _crc_a(cls, data: bytes) -> int:
        return cls._crc16(data, 0x6363)

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

