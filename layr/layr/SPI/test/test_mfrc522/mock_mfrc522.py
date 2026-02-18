from __future__ import annotations

from collections import deque
from typing import Deque, List, Optional, Sequence

import cocotb
from cocotb.triggers import Timer
from cocotbext.spi import SpiSlaveBase, SpiConfig


class Mfrc522SpiSlave(SpiSlaveBase):
    """
    MFRC522 SPI mock (register + FIFO + minimal command hooks).

    SPI protocol (datasheet section 8.1.2):
      - First byte is address byte: bit7=R/W (1=read), bits6..1=addr, bit0=0
      - Write: addr byte, then data bytes
      - Read: addr byte, then clock out data while sending next addr or 0x00
    """

    # --- Register addresses (6-bit address space) ---
    REG_COMMAND = 0x01
    REG_COM_IEN = 0x02
    REG_DIV_IEN = 0x03
    REG_COM_IRQ = 0x04
    REG_DIV_IRQ = 0x05
    REG_ERROR = 0x06
    REG_STATUS1 = 0x07
    REG_STATUS2 = 0x08
    REG_FIFO_DATA = 0x09
    REG_FIFO_LEVEL = 0x0A
    REG_WATER_LEVEL = 0x0B
    REG_CONTROL = 0x0C
    REG_BIT_FRAMING = 0x0D
    REG_COLL = 0x0E

    REG_MODE = 0x11
    REG_TX_MODE = 0x12
    REG_RX_MODE = 0x13
    REG_TX_CONTROL = 0x14
    REG_TX_ASK = 0x15
    REG_MOD_WIDTH = 0x24

    REG_T_MODE = 0x2A
    REG_T_PRESCALER = 0x2B
    REG_T_RELOAD_H = 0x2C
    REG_T_RELOAD_L = 0x2D

    REG_CRC_RESULT_MSB = 0x21
    REG_CRC_RESULT_LSB = 0x22

    REG_VERSION = 0x37

    # --- Bits in ComIrqReg ---
    COMIRQ_TIMER = 1 << 0
    COMIRQ_ERR = 1 << 1
    COMIRQ_LOALERT = 1 << 2
    COMIRQ_HIALERT = 1 << 3
    COMIRQ_IDLE = 1 << 4
    COMIRQ_RX = 1 << 5
    COMIRQ_TX = 1 << 6
    COMIRQ_SET1 = 1 << 7

    # --- Bits in DivIrqReg ---
    DIVIRQ_CRCIRq = 1 << 2
    DIVIRQ_MFINACT = 1 << 4
    DIVIRQ_SET2 = 1 << 7

    # --- Bits in ErrorReg ---
    ERR_PROTOCOL = 1 << 0
    ERR_PARITY = 1 << 1
    ERR_CRC = 1 << 2
    ERR_COLLISION = 1 << 3
    ERR_BUFFER_OVFL = 1 << 4
    ERR_TEMP_ERR = 1 << 6
    ERR_WR_ERR = 1 << 7

    # --- Bits in Status1Reg ---
    STATUS1_LOALERT = 1 << 0
    STATUS1_HIALERT = 1 << 1
    STATUS1_TRUNNING = 1 << 3
    STATUS1_IRQ = 1 << 4
    STATUS1_CRCREADY = 1 << 5
    STATUS1_CRCOK = 1 << 6

    # --- Bits in Status2Reg ---
    STATUS2_MODEMSTATE_MASK = 0x07
    STATUS2_MFCRYPTO1ON = 1 << 3

    # --- Bits in CollReg ---
    COLL_VALUES_AFTER_COLL = 1 << 7
    COLL_POS_NOT_VALID = 1 << 5
    COLL_POS_MASK = 0x1F

    # --- Command codes ---
    CMD_IDLE = 0x00
    CMD_MEM = 0x01
    CMD_GEN_RANDOM_ID = 0x02
    CMD_CALCCRC = 0x03
    CMD_TRANSMIT = 0x04
    CMD_NO_CMD_CHANGE = 0x07
    CMD_RECEIVE = 0x08
    CMD_TRANSCEIVE = 0x0C
    CMD_MF_AUTHENT = 0x0E
    CMD_SOFTRESET = 0x0F

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

        # Card UID for PICC emulation
        self._uid = bytes((0xDE, 0xAD, 0xBE, 0xEF))
        self._version = 0x92  # MFRC522 v2.0

        # Test injection hooks
        self._inject_error: int = 0x00
        self._inject_timeout: bool = False

        # Card presence simulation
        self._card_present: bool = True

        # SPI byte tracking
        self.spi_bytes_sent: List[int] = []  # Bytes sent TO master (MISO)
        self.spi_bytes_received: List[int] = []  # Bytes received FROM master (MOSI)

        # FIFO alert edge tracking
        self._prev_hialert: bool = False
        self._prev_loalert: bool = False

        # State tracking
        self._initialized: bool = False
        self._antenna_on: bool = False
        self._transceive_pending: bool = False

        # Timer state
        self._timer_running: bool = False
        self._timer_reload: int = 0x0000

        self._reset_regs()

    # -------------------------
    # SPI helpers
    # -------------------------
    @staticmethod
    def _decode_addr_byte(addr_byte: int) -> tuple[bool, int]:
        """Decode MFRC522 SPI address byte -> (is_read, addr)."""
        is_read = bool(addr_byte & 0x80)
        addr = (addr_byte >> 1) & 0x3F
        return is_read, addr

    @staticmethod
    def _looks_like_addr_byte_for_read(byte_val: int) -> bool:
        """Check if byte looks like a valid read address byte."""
        return (byte_val & 0x81) == 0x80

    # -------------------------
    # CPHA=0 MISO pre-drive
    # -------------------------
    async def _shift(self, num_bits, tx_word=None):
        """Override to pre-drive MSB on MISO for CPHA=0."""
        if not self._config.cpha and tx_word is not None:
            msb = bool(tx_word & (1 << (num_bits - 1)))
            self._miso.value = int(msb)
            shifted_tx = (tx_word << 1) & ((1 << num_bits) - 1)
            return await super()._shift(num_bits, tx_word=shifted_tx)
        return await super()._shift(num_bits, tx_word=tx_word)

    # -------------------------
    # Public test helpers
    # -------------------------
    async def get_last_frame(self) -> List[int]:
        await self.idle.wait()
        return list(self._last_frame)

    def preload_fifo(self, data: Sequence[int]) -> None:
        """Preload FIFO with bytes for testing."""
        for b in data:
            self._fifo_push(b & 0xFF)

    def set_uid(self, uid: bytes) -> None:
        """Set the card UID for PICC emulation."""
        self._uid = uid[:4] if len(uid) >= 4 else uid + b"\x00" * (4 - len(uid))

    def set_card_present(self, present: bool) -> None:
        """Control card visibility for PICC emulation."""
        self._card_present = present

    def get_spi_bytes_sent(self) -> List[int]:
        """Get all bytes sent to master (MISO)."""
        return list(self.spi_bytes_sent)

    def get_spi_bytes_received(self) -> List[int]:
        """Get all bytes received from master (MOSI)."""
        return list(self.spi_bytes_received)

    def clear_spi_byte_tracking(self) -> None:
        """Clear the SPI byte tracking arrays."""
        self.spi_bytes_sent.clear()
        self.spi_bytes_received.clear()

    # -------------------------
    # Register model
    # -------------------------
    def _reset_regs(self) -> None:
        """Reset all registers to power-on defaults (datasheet section 9.3)."""
        self._regs = [0x00] * 64
        self._fifo.clear()

        # CommandReg: PowerDown=0, RcvOff=1 at reset
        self._regs[self.REG_COMMAND] = 0x20

        # Interrupt registers
        self._regs[self.REG_COM_IEN] = 0x80  # IRqInv=1
        self._regs[self.REG_DIV_IEN] = 0x00
        self._regs[self.REG_COM_IRQ] = 0x14  # IdleIRq + LoAlertIRq
        self._regs[self.REG_DIV_IRQ] = 0x00
        self._regs[self.REG_ERROR] = 0x00
        self._regs[self.REG_STATUS1] = 0x21  # CRCReady + LoAlert
        self._regs[self.REG_STATUS2] = 0x00

        # FIFO / framing
        self._regs[self.REG_WATER_LEVEL] = 0x08
        self._regs[self.REG_CONTROL] = 0x10
        self._regs[self.REG_BIT_FRAMING] = 0x00
        self._regs[self.REG_COLL] = 0x80  # ValuesAfterColl=1

        # TX/RX mode
        self._regs[self.REG_TX_MODE] = 0x00
        self._regs[self.REG_RX_MODE] = 0x00
        self._regs[self.REG_TX_CONTROL] = 0x00  # Antenna off at reset
        self._regs[self.REG_TX_ASK] = 0x00
        self._regs[self.REG_MOD_WIDTH] = 0x26

        # Mode / CRC
        self._regs[self.REG_MODE] = 0x3F
        self._regs[self.REG_CRC_RESULT_MSB] = 0xFF
        self._regs[self.REG_CRC_RESULT_LSB] = 0xFF

        # Timer
        self._regs[self.REG_T_MODE] = 0x00
        self._regs[self.REG_T_PRESCALER] = 0x00
        self._regs[self.REG_T_RELOAD_H] = 0x00
        self._regs[self.REG_T_RELOAD_L] = 0x00

        # Version
        self._regs[self.REG_VERSION] = self._version

        # State
        self._antenna_on = False
        self._transceive_pending = False
        self._timer_running = False

        # Initialize alert edge trackers
        hialert, loalert = self._compute_alerts()
        self._prev_hialert = hialert
        self._prev_loalert = loalert

        self._update_alerts_and_irq()

    def _compute_alerts(self) -> tuple[bool, bool]:
        """Compute HiAlert/LoAlert from FIFO level and WaterLevel."""
        water = self._regs[self.REG_WATER_LEVEL] & 0x3F
        flen = len(self._fifo)
        hialert = (64 - flen) <= water
        loalert = flen <= water
        return hialert, loalert

    def _update_status1_irq(self) -> None:
        """Update Status1Reg.IRq based on enabled pending interrupts."""
        com_en = self._regs[self.REG_COM_IEN] & 0x7F
        div_en = self._regs[self.REG_DIV_IEN] & 0x14  # MfinActIEn + CRCIEn

        com_pending = (self._regs[self.REG_COM_IRQ] & 0x7F) & com_en
        div_pending = (self._regs[self.REG_DIV_IRQ] & 0x7F) & div_en

        if com_pending | div_pending:
            self._regs[self.REG_STATUS1] |= self.STATUS1_IRQ
        else:
            self._regs[self.REG_STATUS1] &= ~self.STATUS1_IRQ

    def _update_alerts_and_irq(self) -> None:
        """Update Status1Reg alerts and edge-latch IRQs."""
        hialert, loalert = self._compute_alerts()

        # Update Status1Reg level bits
        s1 = self._regs[self.REG_STATUS1]
        s1 &= ~(self.STATUS1_HIALERT | self.STATUS1_LOALERT)
        if hialert:
            s1 |= self.STATUS1_HIALERT
        if loalert:
            s1 |= self.STATUS1_LOALERT
        self._regs[self.REG_STATUS1] = s1

        # Edge-latch Hi/LoAlertIRq
        if hialert and not self._prev_hialert:
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_HIALERT
        if loalert and not self._prev_loalert:
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_LOALERT
        self._prev_hialert = hialert
        self._prev_loalert = loalert

        # ErrIRq when any error bit set
        if self._regs[self.REG_ERROR] != 0:
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_ERR

        self._update_status1_irq()

    def _fifo_push(self, b: int) -> None:
        if len(self._fifo) >= 64:
            self._regs[self.REG_ERROR] |= self.ERR_BUFFER_OVFL
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_ERR
            cocotb.log.warning("MFRC522: FIFO overflow")
            return
        self._fifo.append(b & 0xFF)
        self._update_alerts_and_irq()

    def _fifo_pop(self) -> int:
        if not self._fifo:
            return 0x00
        b = self._fifo.popleft()
        self._update_alerts_and_irq()
        return b

    def _fifo_flush(self) -> None:
        """Flush FIFO and clear BufferOvfl error."""
        self._fifo.clear()
        self._regs[self.REG_ERROR] &= ~self.ERR_BUFFER_OVFL
        self._update_alerts_and_irq()
        cocotb.log.debug("MFRC522: FIFO flushed")

    def _read_reg(self, addr: int) -> int:
        addr &= 0x3F

        if addr == self.REG_FIFO_DATA:
            return self._fifo_pop()

        if addr == self.REG_FIFO_LEVEL:
            return len(self._fifo) & 0x7F

        if addr == self.REG_STATUS1:
            self._update_alerts_and_irq()
            return self._regs[addr] & 0x7B

        if addr == self.REG_STATUS2:
            return self._regs[addr] & 0x0F

        if addr == self.REG_COM_IRQ:
            return self._regs[addr] & 0x7F

        if addr == self.REG_DIV_IRQ:
            return self._regs[addr] & 0x7F

        if addr == self.REG_ERROR:
            return self._regs[addr]

        if addr == self.REG_BIT_FRAMING:
            # StartSend (bit7) reads as 0
            return self._regs[addr] & 0x7F

        if addr == self.REG_CONTROL:
            # TStopNow, TStartNow (bits 7:6) read as 0
            return self._regs[addr] & 0x3F

        if addr == self.REG_COLL:
            return self._regs[addr]

        if addr == self.REG_WATER_LEVEL:
            return self._regs[addr] & 0x3F

        return self._regs[addr] & 0xFF

    def _unread_reg(self, addr: int, value: int) -> None:
        """Undo destructive read for FIFO."""
        if (addr & 0x3F) == self.REG_FIFO_DATA:
            self._fifo.appendleft(value & 0xFF)
            self._update_alerts_and_irq()

    def _write_reg(self, addr: int, data: int) -> None:
        addr &= 0x3F
        data &= 0xFF

        # Read-only registers
        if addr in (
            self.REG_STATUS1,
            self.REG_ERROR,
            self.REG_CRC_RESULT_MSB,
            self.REG_CRC_RESULT_LSB,
            self.REG_VERSION,
        ):
            return

        if addr == self.REG_COMMAND:
            self._handle_command_write(data)
            return

        if addr == self.REG_COM_IEN:
            self._regs[addr] = data
            self._update_status1_irq()
            return

        if addr == self.REG_DIV_IEN:
            self._regs[addr] = data & 0x94  # Valid bits only
            self._update_status1_irq()
            return

        if addr == self.REG_COM_IRQ:
            # Set1 bit controls set/clear behavior
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

        if addr == self.REG_FIFO_DATA:
            self._fifo_push(data)
            return

        if addr == self.REG_FIFO_LEVEL:
            # Bit7 = FlushBuffer
            if data & 0x80:
                self._fifo_flush()
            return

        if addr == self.REG_WATER_LEVEL:
            self._regs[addr] = data & 0x3F
            self._update_alerts_and_irq()
            return

        if addr == self.REG_BIT_FRAMING:
            self._regs[addr] = data
            # StartSend triggers transceive if command is active
            if data & 0x80:
                self._maybe_start_transceive()
            return

        if addr == self.REG_COLL:
            # Only ValuesAfterColl (bit7) is writable
            self._regs[addr] = (self._regs[addr] & 0x3F) | (data & 0x80)
            return

        if addr == self.REG_TX_CONTROL:
            old_antenna = self._antenna_on
            self._antenna_on = (data & 0x03) == 0x03
            self._regs[addr] = data
            if self._antenna_on and not old_antenna:
                cocotb.log.info("MFRC522: Antenna ON")
            elif not self._antenna_on and old_antenna:
                cocotb.log.info("MFRC522: Antenna OFF")
            return

        if addr == self.REG_CONTROL:
            # TStopNow (bit7) and TStartNow (bit6) are triggers
            if data & 0x80:
                self._timer_running = False
            if data & 0x40:
                self._timer_running = True
            # Store only persistent bits
            self._regs[addr] = (self._regs[addr] & 0xC0) | (data & 0x3F)
            return

        if addr == self.REG_T_RELOAD_H:
            self._regs[addr] = data
            self._timer_reload = (data << 8) | (self._regs[self.REG_T_RELOAD_L])
            return

        if addr == self.REG_T_RELOAD_L:
            self._regs[addr] = data
            self._timer_reload = (self._regs[self.REG_T_RELOAD_H] << 8) | data
            return

        # Default store
        self._regs[addr] = data

    def _handle_command_write(self, data: int) -> None:
        """Handle write to CommandReg."""
        cmd = data & 0x0F
        power_down = bool(data & 0x10)

        # Clear errors on command start (except TempErr and BufferOvfl)
        if cmd not in (self.CMD_IDLE, self.CMD_NO_CMD_CHANGE):
            preserve = self._regs[self.REG_ERROR] & (
                self.ERR_TEMP_ERR | self.ERR_BUFFER_OVFL
            )
            self._regs[self.REG_ERROR] = preserve

        self._regs[self.REG_COMMAND] = data

        cmd_names = {
            0x00: "Idle",
            0x01: "Mem",
            0x02: "GenerateRandomID",
            0x03: "CalcCRC",
            0x04: "Transmit",
            0x07: "NoCmdChange",
            0x08: "Receive",
            0x0C: "Transceive",
            0x0E: "MFAuthent",
            0x0F: "SoftReset",
        }
        cocotb.log.debug(f"MFRC522: Command = {cmd_names.get(cmd, f'0x{cmd:02X}')}")

        if cmd == self.CMD_SOFTRESET:
            cocotb.log.info("MFRC522: Soft reset")
            self._reset_regs()
            self._initialized = True
            return

        if cmd == self.CMD_CALCCRC:
            cocotb.start_soon(self._do_calccrc())
            return

        if cmd == self.CMD_TRANSCEIVE:
            self._transceive_pending = True
            self._maybe_start_transceive()
            return

        if cmd == self.CMD_IDLE:
            self._transceive_pending = False
            # IdleIRq is set when returning to idle
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_IDLE
            self._update_status1_irq()
            return

        self._update_alerts_and_irq()

    def _maybe_start_transceive(self) -> None:
        """Start transceive if conditions are met."""
        cmd = self._regs[self.REG_COMMAND] & 0x0F
        start_send = bool(self._regs[self.REG_BIT_FRAMING] & 0x80)

        if cmd == self.CMD_TRANSCEIVE and start_send and self._transceive_pending:
            self._transceive_pending = False
            cocotb.start_soon(self._do_transceive())

    async def _do_transceive(self) -> None:
        """ISO/IEC 14443-A PICC emulation for REQA/ANTICOLL/SELECT."""

        # Check preconditions
        if not self._initialized:
            cocotb.log.warning("MFRC522: Transceive ignored - not initialized")
            self._set_timeout()
            return

        if not self._antenna_on:
            cocotb.log.warning("MFRC522: Transceive ignored - antenna off")
            self._set_timeout()
            return

        # Handle test injection
        if self._inject_timeout:
            cocotb.log.info("MFRC522: Injected timeout")
            self._set_timeout()
            return

        # Get TX data from FIFO
        tx_last_bits = self._regs[self.REG_BIT_FRAMING] & 0x07
        req = bytes(self._fifo)
        self._fifo.clear()

        cocotb.log.info(
            f"MFRC522: TX [{len(req)} bytes, {tx_last_bits} last bits]: {req.hex() if req else '(empty)'}"
        )

        # Process command and generate response
        resp, rx_last_bits = self._process_picc_command(req, tx_last_bits)

        # Clear StartSend
        self._regs[self.REG_BIT_FRAMING] &= ~0x80

        if resp:
            # Load response into FIFO
            for b in resp:
                self._fifo_push(b)

            # Update ControlReg RxLastBits
            self._regs[self.REG_CONTROL] = (self._regs[self.REG_CONTROL] & 0xF8) | (
                rx_last_bits & 0x07
            )

            # Set completion IRQs
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_RX | self.COMIRQ_IDLE

            cocotb.log.info(f"MFRC522: RX [{len(resp)} bytes]: {resp.hex()}")
        else:
            # No response - timeout
            self._set_timeout()

        # Apply injected errors
        if self._inject_error:
            self._regs[self.REG_ERROR] |= self._inject_error
            self._regs[self.REG_COM_IRQ] |= self.COMIRQ_ERR

        self._update_alerts_and_irq()

    def _process_picc_command(self, req: bytes, tx_last_bits: int) -> tuple[bytes, int]:
        """
        Process PICC command and return (response, rx_last_bits).

        Supports:
          - REQA (0x26) / WUPA (0x52) with 7-bit frame -> ATQA
          - ANTICOLL CL1 (0x93 0x20) -> UID + BCC
          - SELECT CL1 (0x93 0x70 ...) -> SAK + CRC
        """
        rx_last_bits = 0

        # Strip trailing zeros for all commands
        req_stripped = req.rstrip(b"\x00")

        # REQA/WUPA: 7-bit command (single byte, may be padded)
        if tx_last_bits == 7 and len(req_stripped) == 1:
            if req_stripped[0] in (0x26, 0x52):
                if not self._card_present:
                    cocotb.log.debug(
                        f"MFRC522: {req_stripped[0] == 0x26 and 'REQA' or 'WUPA'} received, no card present"
                    )
                    return b"", 0
                cmd_name = "REQA" if req_stripped[0] == 0x26 else "WUPA"
                cocotb.log.debug(f"MFRC522: {cmd_name} received")
                # ATQA for MIFARE Classic 1K: 0x04 0x00
                return b"\x04\x00", 0

        # ANTICOLL CL1
        if req_stripped == b"\x93\x20":
            uid = self._uid[:4]
            bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3]
            cocotb.log.debug(f"MFRC522: ANTICOLL CL1, responding with UID")
            return uid + bytes([bcc]), 0

        # SELECT CL1: 0x93 0x70 + UID(4) + BCC + CRC_A(2) = 9 bytes
        if (
            len(req_stripped) >= 7
            and req_stripped[0] == 0x93
            and req_stripped[1] == 0x70
        ):
            uid = self._uid[:4]
            uid_in = req_stripped[2:6]
            bcc_in = req_stripped[6] if len(req_stripped) > 6 else 0

            expected_bcc = uid_in[0] ^ uid_in[1] ^ uid_in[2] ^ uid_in[3]

            if uid_in == uid and bcc_in == expected_bcc:
                # SAK for MIFARE Classic: 0x08
                sak = 0x08
                crc = self._crc_a(bytes([sak]))
                cocotb.log.debug(f"MFRC522: SELECT CL1 OK, responding with SAK")
                return bytes([sak, crc & 0xFF, (crc >> 8) & 0xFF]), 0
            else:
                cocotb.log.debug(f"MFRC522: SELECT UID mismatch")
                return b"", 0

        # Unknown command
        cocotb.log.debug(
            f"MFRC522: Unknown PICC command: {req.hex() if req else '(empty)'}, tx_last_bits={tx_last_bits}"
        )
        return b"", 0

    def _set_timeout(self) -> None:
        """Set timeout condition (TimerIRq)."""
        self._regs[self.REG_COM_IRQ] |= self.COMIRQ_TIMER | self.COMIRQ_IDLE
        self._regs[self.REG_BIT_FRAMING] &= ~0x80
        self._update_alerts_and_irq()

    async def _do_calccrc(self) -> None:
        """Emulate CalcCRC command."""
        # Clear CRCReady during calculation
        self._regs[self.REG_STATUS1] &= ~(self.STATUS1_CRCREADY | self.STATUS1_CRCOK)

        await Timer(50, units="ns")

        # Calculate CRC over FIFO contents
        data = bytes(self._fifo)

        # Get preset from ModeReg
        mode = self._regs[self.REG_MODE]
        preset_sel = mode & 0x03
        preset = {
            0: 0x0000,
            1: 0x6363,  # ISO 14443-A
            2: 0xA671,
            3: 0xFFFF,
        }[preset_sel]

        crc = self._crc16(data, preset)

        msb = (crc >> 8) & 0xFF
        lsb = crc & 0xFF

        # MSBFirst bit reverses output
        if mode & 0x80:
            msb = self._bit_reverse8(msb)
            lsb = self._bit_reverse8(lsb)

        self._regs[self.REG_CRC_RESULT_MSB] = msb
        self._regs[self.REG_CRC_RESULT_LSB] = lsb

        # Set completion flags
        self._regs[self.REG_DIV_IRQ] |= self.DIVIRQ_CRCIRq
        self._regs[self.REG_STATUS1] |= self.STATUS1_CRCREADY
        self._regs[self.REG_COM_IRQ] |= self.COMIRQ_IDLE

        if crc == 0:
            self._regs[self.REG_STATUS1] |= self.STATUS1_CRCOK

        self._update_alerts_and_irq()
        cocotb.log.debug(f"MFRC522: CRC complete = 0x{crc:04X}")

    @staticmethod
    def _bit_reverse8(x: int) -> int:
        x &= 0xFF
        x = ((x & 0xF0) >> 4) | ((x & 0x0F) << 4)
        x = ((x & 0xCC) >> 2) | ((x & 0x33) << 2)
        x = ((x & 0xAA) >> 1) | ((x & 0x55) << 1)
        return x

    @staticmethod
    def _crc16(data: bytes, preset: int) -> int:
        """CRC-16 with polynomial x^16 + x^12 + x^5 + 1 (LSB-first)."""
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
        """ISO 14443-A CRC with preset 0x6363."""
        return cls._crc16(data, 0x6363)

    # -------------------------
    # SPI transaction handling
    # -------------------------
    async def _shift_byte_or_end(self, frame_end, tx: int) -> Optional[int]:
        """Shift one byte while watching for frame end."""
        from cocotb.triggers import RisingEdge, FallingEdge, First

        if self._config.cs_active_low:
            fe = RisingEdge(self._cs)
        else:
            fe = FallingEdge(self._cs)

        task = cocotb.start_soon(self._shift(8, tx_word=(tx & 0xFF)))
        done = await First(task, fe)

        if done is fe:
            task.cancel()
            return None

        rx_byte = int(task.result()) & 0xFF

        # Track SPI bytes
        self.spi_bytes_sent.append(tx & 0xFF)
        self.spi_bytes_received.append(rx_byte)

        return rx_byte

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()
        self._last_frame = []

        # First byte: address
        addr_byte = await self._shift_byte_or_end(frame_end, tx=0x00)
        if addr_byte is None:
            self.idle.set()
            return

        self._last_frame.append(addr_byte)
        is_read, addr = self._decode_addr_byte(addr_byte)

        if is_read:
            # Read transaction
            while True:
                fifo_len_before = len(self._fifo)
                tx = self._read_reg(addr)
                rx = await self._shift_byte_or_end(frame_end, tx=tx)

                if rx is None:
                    # Frame ended - undo destructive FIFO read if needed
                    if (addr & 0x3F) == self.REG_FIFO_DATA and len(
                        self._fifo
                    ) < fifo_len_before:
                        self._unread_reg(addr, tx)
                    break

                self._last_frame.append(rx)

                # Support sequential register reads
                if self._looks_like_addr_byte_for_read(rx):
                    _, addr = self._decode_addr_byte(rx)
        else:
            # Write transaction
            while True:
                data = await self._shift_byte_or_end(frame_end, tx=0x00)
                if data is None:
                    break
                self._last_frame.append(data)
                self._write_reg(addr, data)

        self.idle.set()
