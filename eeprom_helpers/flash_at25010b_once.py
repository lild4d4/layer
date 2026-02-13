#!/usr/bin/env python3
"""
Flash an AT25010B SPI EEPROM via FT232H (MPSSE/SPI).

AT25010B specs:
  - 1Kbit (128 bytes) SPI EEPROM
  - 8-byte page size
  - 8-bit addressing
  - Max SPI clock: 20MHz
  - Write cycle time: ~5ms

Memory layout:
  0x00 - 0x0F: Key A (16 bytes)
  0x10 - 0x1F: Key B (16 bytes)
  0x20 - 0x2F: Key C (16 bytes)
  0x30 - 0x3F: Key D (16 bytes)
  0x40 - 0x4F: ID A  (16 bytes)
  0x50 - 0x5F: ID B  (16 bytes)
  0x60 - 0x6F: ID C  (16 bytes)
  0x70 - 0x7F: ID D  (16 bytes)

Wiring (FT232H -> AT25010B):
  AD0 (SCK)  -> Pin 6 (SCK)
  AD1 (MOSI) -> Pin 5 (SI)
  AD2 (MISO) -> Pin 2 (SO)
  AD3 (CS)   -> Pin 1 (CS#)
  GND        -> Pin 4 (GND)
  3.3V       -> Pin 8 (VCC), Pin 7 (HOLD#), Pin 3 (WP#)

Usage:
  pip install pyftdi
  python flash_eeprom.py
"""

import time
import sys
from pyftdi.spi import SpiController

# --- SPI EEPROM opcodes (AT25010B) ---
OPCODE_WREN = 0x06  # Write Enable
OPCODE_WRDI = 0x04  # Write Disable
OPCODE_RDSR = 0x05  # Read Status Register
OPCODE_WRSR = 0x01  # Write Status Register
OPCODE_READ = 0x03  # Read Data
OPCODE_WRITE = 0x02  # Write Data

PAGE_SIZE = 8  # AT25010B page size in bytes
CHIP_SIZE = 128  # AT25010B total size in bytes
WRITE_CYCLE = 0.006  # 6ms (datasheet says 5ms typ, add margin)

# --- Data to write ---
WRITE_BLOCKS = [
    # Keys: 0x00 - 0x3F
    {
        "address": 0x00,
        "label": "Key A",
        "data": bytes.fromhex("39558d1f193656ab8b4b65e25ac48474"),
    },
    {
        "address": 0x10,
        "label": "Key B",
        "data": bytes.fromhex("35d78ceccb60461ff7dbcb341caeea00"),
    },
    {
        "address": 0x20,
        "label": "Key C",
        "data": bytes.fromhex("25d872b92bcf115fd929bd9acf2fd49d"),
    },
    {
        "address": 0x30,
        "label": "Key D",
        "data": bytes.fromhex("0614e9e59a36d7d9d43b80ed04b84001"),
    },
    # IDs: 0x40 - 0x7F
    {
        "address": 0x40,
        "label": "ID A",
        "data": bytes.fromhex("bbe8278a67f960605adafd6f63cf7ba7"),
    },
    {
        "address": 0x50,
        "label": "ID B",
        "data": bytes.fromhex("d0d23f18251c6087566de7b7deab7774"),
    },
    {
        "address": 0x60,
        "label": "ID C",
        "data": bytes.fromhex("28d7c47f5bd16c9814a142aa4ba28823"),
    },
    {
        "address": 0x70,
        "label": "ID D",
        "data": bytes.fromhex("c88d1dd2085fb8b40efb83cf2f6c6c6f"),
    },
]

# --- FTDI URL (adjust if you have multiple FTDI devices) ---
FTDI_URL = "ftdi://ftdi:232h/1"
SPI_FREQ = 1_000_000  # 1 MHz (conservative, AT25010B supports up to 20MHz)


class AT25010B:
    def __init__(self, ftdi_url: str = FTDI_URL, freq: int = SPI_FREQ):
        self.ctrl = SpiController()
        self.ctrl.configure(ftdi_url)
        self.slave = self.ctrl.get_port(cs=0, freq=freq, mode=0)

    def close(self):
        self.ctrl.terminate()

    def _read_status(self) -> int:
        resp = self.slave.exchange([OPCODE_RDSR], readlen=1)
        return resp[0]

    def _wait_ready(self, timeout: float = 1.0):
        """Poll the WIP (Write-In-Progress) bit until the chip is ready."""
        start = time.time()
        while True:
            status = self._read_status()
            if not (status & 0x01):  # WIP bit clear
                return
            if time.time() - start > timeout:
                raise TimeoutError("EEPROM write cycle timeout")
            time.sleep(0.001)

    def _write_enable(self):
        self.slave.exchange([OPCODE_WREN])

    def write_page(self, address: int, data: bytes):
        """
        Write up to PAGE_SIZE bytes starting at `address`.
        Address + len(data) must not cross a page boundary.
        """
        if len(data) > PAGE_SIZE:
            raise ValueError(f"Data exceeds page size ({PAGE_SIZE} bytes)")
        if len(data) == 0:
            return
        page_start = (address // PAGE_SIZE) * PAGE_SIZE
        if address + len(data) > page_start + PAGE_SIZE:
            raise ValueError("Write would cross a page boundary")

        self._write_enable()
        cmd = bytes([OPCODE_WRITE, address & 0xFF]) + data
        self.slave.exchange(cmd)
        time.sleep(WRITE_CYCLE)
        self._wait_ready()

    def write(self, address: int, data: bytes):
        """Write arbitrary length data, automatically splitting across pages."""
        offset = 0
        while offset < len(data):
            current_addr = address + offset
            page_offset = current_addr % PAGE_SIZE
            chunk_size = min(PAGE_SIZE - page_offset, len(data) - offset)
            chunk = data[offset : offset + chunk_size]

            self.write_page(current_addr, chunk)
            offset += chunk_size

    def read(self, address: int, length: int) -> bytes:
        """Read `length` bytes starting at `address`."""
        cmd = [OPCODE_READ, address & 0xFF]
        resp = self.slave.exchange(cmd, readlen=length)
        return bytes(resp)

    def verify(self, address: int, expected: bytes) -> bool:
        """Read back and compare against expected data."""
        actual = self.read(address, len(expected))
        return actual == expected


def main():
    print("AT25010B EEPROM Programmer via FT232H")
    print("=" * 42)

    try:
        eeprom = AT25010B()
    except Exception as e:
        print(f"\nERROR: Could not open FT232H: {e}")
        print("Check wiring and that the device is connected.")
        sys.exit(1)

    try:
        # Show current status
        status = eeprom._read_status()
        print(f"EEPROM status register: 0x{status:02X}")

        # Clear block protection bits if set (bits 2-3)
        if status & 0x0C:
            print("Clearing write protection bits...")
            eeprom._write_enable()
            eeprom.slave.exchange([OPCODE_WRSR, 0x00])
            time.sleep(WRITE_CYCLE)
            eeprom._wait_ready()

        # Write each block
        for block in WRITE_BLOCKS:
            addr = block["address"]
            data = block["data"]
            label = block["label"]
            print(f"\nWriting {label} ({len(data)} bytes) to address 0x{addr:02X}...")
            print(f"  Data: {data.hex()}")
            eeprom.write(addr, data)
            print("  Write complete.")

            # Verify
            print("  Verifying...", end=" ")
            if eeprom.verify(addr, data):
                print("OK")
            else:
                readback = eeprom.read(addr, len(data))
                print("FAILED!")
                print(f"  Expected: {data.hex()}")
                print(f"  Got:      {readback.hex()}")
                sys.exit(1)

        # Final full dump
        print("\n" + "=" * 42)
        print("Verification complete. Full EEPROM dump:")
        dump = eeprom.read(0x00, CHIP_SIZE)
        for i in range(0, len(dump), 16):
            hex_part = " ".join(f"{b:02X}" for b in dump[i : i + 16])
            print(f"  0x{i:02X}: {hex_part}")

        print("\nDone! EEPROM programmed successfully.")

    finally:
        eeprom.close()


if __name__ == "__main__":
    main()
