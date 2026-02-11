"""
AT25010B SPI EEPROM Mock for cocotb simulation.

Memory:     128 bytes (1 Kbit)
Address:    7-bit (A6:A0)
Protocol:   SPI Mode 0 or 3, MSB-first, CS active-low

The ONLY method provided by SpiSlaveBase is:

    received = await self._shift(n_bits, tx_word=0)

It simultaneously:
  - clocks in `n_bits` bits from MOSI  →  returns received integer
  - drives  `n_bits` bits from `tx_word` onto MISO (MSB-first)

There is NO separate _shift_in / _shift_out. Every byte exchange uses
_shift(8, tx_word=<miso_byte>). When we only care about MOSI (receiving a
command / address / data byte) we pass tx_word=0 so MISO idles low.
When we only care about MISO (sending data back) the return value is discarded.

Opcodes
-------
WREN  = 0x06  Set Write Enable Latch (WEL)
WRDI  = 0x04  Reset Write Enable Latch
RDSR  = 0x05  Read Status Register
WRSR  = 0x01  Write Status Register (BP1, BP0, SRWD bits only)
READ  = 0x03  Read Data Bytes
WRITE = 0x02  Write Data Bytes (up to page boundary)

Status Register (SR)
--------------------
  Bit 7 : SRWD  - SR write-protect (not modelled; always 0)
  Bit 4 : BP1   - Block Protect bit 1
  Bit 3 : BP0   - Block Protect bit 0
  Bit 1 : WEL   - Write Enable Latch  (read-only from outside)
  Bit 0 : WIP   - Write In Progress   (always 0; writes are instant)

Block-protect (BP1:BP0)
-----------------------
  00  no protection
  01  upper quarter  (0x60-0x7F) protected
  10  upper half     (0x40-0x7F) protected
  11  entire array   (0x00-0x7F) protected

Usage
-----
    from cocotbext.spi import SpiBus
    from at25010b_eeprom import AT25010B_EEPROM

    eeprom = AT25010B_EEPROM(SpiBus.from_entity(dut))
    eeprom.memory[0x00] = 0xAB          # pre-load for test
    eeprom.load_memory(b"\\xDE\\xAD", offset=0x10)
"""

import cocotb
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "cocotbext-spi"))
from cocotbext.spi import SpiSlaveBase, SpiConfig

# ---------------------------------------------------------------------------
# Opcode constants
# ---------------------------------------------------------------------------
_WREN = 0x06
_WRDI = 0x04
_RDSR = 0x05
_WRSR = 0x01
_READ = 0x03
_WRITE = 0x02

# Status-register bit masks
_SR_WIP = 0x01
_SR_WEL = 0x02
_SR_BP0 = 0x08
_SR_BP1 = 0x10
_SR_SRWD = 0x80

# Bits writable via WRSR (WIP and WEL are read-only from outside)
_SR_WRITABLE_MASK = _SR_SRWD | _SR_BP1 | _SR_BP0

_MEMORY_SIZE = 128  # bytes
_PAGE_SIZE = 8  # bytes


class AT25010B_EEPROM(SpiSlaveBase):
    """
    Behavioural model of the Adesto / Renesas AT25010B 1-Kbit SPI EEPROM.

    Writes complete instantly (WIP is never set). See _handle_write() for
    how to add simulated write-cycle delay if your DUT polls WIP.

    Attributes
    ----------
    memory : bytearray
        Direct access to the 128-byte array for test setup / inspection.
    status_register : int
        Current value of the 8-bit status register.
    """

    def __init__(self, bus):
        # word_width=8 so each _shift() call exchanges exactly one byte.
        self._config = SpiConfig(
            word_width=8,
            sclk_freq=None,
            cpol=False,  # SPI Mode 0
            cpha=False,
            msb_first=True,
            cs_active_low=True,
        )
        super().__init__(bus)

        self.memory = bytearray(_MEMORY_SIZE)
        self.status_register = 0x00  # WIP=0, WEL=0, no block-protect

    # ------------------------------------------------------------------
    # Public helpers for test code
    # ------------------------------------------------------------------

    def load_memory(self, data: bytes, offset: int = 0) -> None:
        """Pre-load *data* into the array starting at *offset*."""
        end = offset + len(data)
        if end > _MEMORY_SIZE:
            raise ValueError(
                f"Data ({len(data)} B) at offset {offset:#04x} "
                f"overflows EEPROM size ({_MEMORY_SIZE} B)"
            )
        self.memory[offset:end] = data

    def dump_memory(self) -> bytes:
        """Return a snapshot of the full 128-byte array."""
        return bytes(self.memory)

    # ------------------------------------------------------------------
    # SpiSlaveBase interface
    # ------------------------------------------------------------------

    async def _transaction(self, frame_start, frame_end):
        """
        Entry point called once per CS-assertion by SpiSlaveBase.

        Protocol:
          1. await frame_start  - wait for the first active SCK edge inside CS
          2. self.idle.clear()  - signal that a transaction is in progress
          3. _shift(8, tx_word=0)  - receive opcode; MISO idles low
          4. dispatch to handler
          5. await frame_end   - consume CS de-assertion edge
          (SpiSlaveBase sets self.idle after _transaction returns)
        """
        await frame_start
        self.idle.clear()

        opcode = int(await self._shift(8, tx_word=0))

        if opcode == _WREN:
            self._handle_wren()
        elif opcode == _WRDI:
            self._handle_wrdi()
        elif opcode == _RDSR:
            await self._handle_rdsr()
        elif opcode == _WRSR:
            await self._handle_wrsr()
        elif opcode == _READ:
            await self._handle_read()
        elif opcode == _WRITE:
            await self._handle_write()
        else:
            cocotb.log.warning(f"AT25010B: unknown opcode {opcode:#04x} - ignoring")

        await frame_end

    # ------------------------------------------------------------------
    # Opcode handlers
    # ------------------------------------------------------------------

    def _handle_wren(self):
        """WREN (0x06): assert WEL. Single-byte transaction."""
        self.status_register |= _SR_WEL
        cocotb.log.debug("AT25010B: WREN - WEL set")

    def _handle_wrdi(self):
        """WRDI (0x04): deassert WEL. Single-byte transaction."""
        self.status_register &= ~_SR_WEL
        cocotb.log.debug("AT25010B: WRDI - WEL cleared")

    async def _handle_rdsr(self):
        """
        RDSR (0x05): shift the status register out on MISO.

        _shift(8, tx_word=status_register) drives MISO with the SR byte
        while simultaneously clocking in the (don't-care) MOSI bits.
        """
        await self._send_status()

    async def _handle_wrsr(self):
        """
        WRSR (0x01): update BP1/BP0/SRWD bits of the status register.

        Requires WEL=1; silently ignored otherwise.
        Only the bits in _SR_WRITABLE_MASK are changed.
        Clears WEL on completion (even if protect bits were unchanged).
        """
        new_sr_byte = int(await self._shift(8, tx_word=0))

        if not (self.status_register & _SR_WEL):
            cocotb.log.warning("AT25010B: WRSR ignored - WEL not set")
            return

        self.status_register = (self.status_register & ~_SR_WRITABLE_MASK) | (
            new_sr_byte & _SR_WRITABLE_MASK
        )
        self.status_register &= ~_SR_WEL
        cocotb.log.debug(f"AT25010B: WRSR - SR now {self.status_register:#04x}")

    async def _handle_read(self):
        """
        READ (0x03): [0x03][ADDR][data out ...]

        Address byte: lower 7 bits; bit 7 ignored.
        Data:         streamed out on MISO; address wraps at 0x7F -> 0x00.

        Each iteration calls _shift(8, tx_word=memory[addr]) which drives
        MISO with the memory byte while clocking in the dummy MOSI byte the
        master sends to generate SCK cycles. The loop ends when the framework
        raises an exception on CS deassertion.
        """
        addr_byte = int(await self._shift(8, tx_word=0))
        addr = addr_byte & 0x7F

        cocotb.log.debug(f"AT25010B: READ from {addr:#04x}")

        try:
            while True:
                await self._shift(8, tx_word=self.memory[addr % _MEMORY_SIZE])
                addr = (addr + 1) % _MEMORY_SIZE
        except Exception:
            pass  # CS deasserted - normal end of streaming read

    async def _handle_write(self):
        """
        WRITE (0x02): [0x02][ADDR][data in ...]

        Requires WEL=1; silently ignored otherwise.
        Data bytes wrap within the current 8-byte page on address overflow
        (matches the real device's page-write behaviour).
        WEL is cleared when CS deasserts regardless of whether any bytes
        were protected.

        Write-cycle timing
        ------------------
        Writes are instantaneous in this model (WIP is never set).
        To simulate the ~5 ms write cycle for a DUT that polls WIP:

            from cocotb.triggers import Timer
            self.status_register |= _SR_WIP
            # ... apply the bytes ...
            await Timer(5, "ms")
            self.status_register &= ~_SR_WIP
        """
        addr_byte = int(await self._shift(8, tx_word=0))
        addr = addr_byte & 0x7F

        if not (self.status_register & _SR_WEL):
            cocotb.log.warning("AT25010B: WRITE ignored - WEL not set")
            return

        page_base = (addr // _PAGE_SIZE) * _PAGE_SIZE
        page_offset = addr % _PAGE_SIZE

        cocotb.log.debug(f"AT25010B: WRITE to {addr:#04x} (page_base={page_base:#04x})")

        byte_count = 0
        try:
            while True:
                data_byte = int(await self._shift(8, tx_word=0))
                write_addr = page_base + page_offset

                if self._is_protected(write_addr):
                    cocotb.log.warning(
                        f"AT25010B: write to {write_addr:#04x} blocked "
                        f"by block-protect (SR={self.status_register:#04x})"
                    )
                else:
                    self.memory[write_addr] = data_byte

                page_offset = (page_offset + 1) % _PAGE_SIZE
                byte_count += 1
        except Exception:
            pass  # CS deasserted - normal end of write

        cocotb.log.debug(f"AT25010B: WRITE complete - {byte_count} byte(s) processed")
        self.status_register &= ~_SR_WEL

    async def _send_status(self):
        """Drive the status register byte onto MISO (used by RDSR)."""
        cocotb.log.debug(f"AT25010B: RDSR - SR={self.status_register:#04x}")
        await self._shift(8, tx_word=self.status_register)

    # ------------------------------------------------------------------
    # Block-protect
    # ------------------------------------------------------------------

    def _is_protected(self, addr: int) -> bool:
        """
        Return True when *addr* falls in the block-protect region.

          BP1 BP0  Protected range
           0   0   None
           0   1   0x60-0x7F  (upper quarter)
           1   0   0x40-0x7F  (upper half)
           1   1   0x00-0x7F  (entire array)
        """
        bp = (self.status_register & (_SR_BP1 | _SR_BP0)) >> 3

        if bp == 0b00:
            return False
        elif bp == 0b01:
            return addr >= 0x60
        elif bp == 0b10:
            return addr >= 0x40
        else:  # 0b11
            return True
