#!/usr/bin/env python3
"""
Debug version: Flash AT25010B SPI EEPROM via FT232H.
Adds extra diagnostics to find the write issue.
"""

import time
import sys
from pyftdi.spi import SpiController

OPCODE_WREN = 0x06
OPCODE_WRDI = 0x04
OPCODE_RDSR = 0x05
OPCODE_WRSR = 0x01
OPCODE_READ = 0x03
OPCODE_WRITE = 0x02

PAGE_SIZE = 8
WRITE_CYCLE = 0.010  # 10ms, extra conservative

FTDI_URL = "ftdi://ftdi:232h/1"
SPI_FREQ = 100_000  # 100 kHz — very slow for debugging


def main():
    print("AT25010B Debug Flash Tool")
    print("=" * 42)

    ctrl = SpiController()
    ctrl.configure(FTDI_URL)
    slave = ctrl.get_port(cs=0, freq=SPI_FREQ, mode=0)

    def read_status():
        return slave.exchange([OPCODE_RDSR], readlen=1)[0]

    def read_data(addr, length):
        return bytes(slave.exchange([OPCODE_READ, addr & 0xFF], readlen=length))

    # --- Step 1: Basic connectivity check ---
    print("\n[1] Status register read:")
    status = read_status()
    print(f"    Status: 0x{status:02X}")
    print(
        f"    WIP={status & 0x01}, WEL={bool(status & 0x02)}, BP0={bool(status & 0x04)}, BP1={bool(status & 0x08)}"
    )

    # --- Step 2: Read current contents ---
    print("\n[2] Current EEPROM contents (first 32 bytes):")
    dump = read_data(0x00, 32)
    for i in range(0, 32, 16):
        hex_part = " ".join(f"{b:02X}" for b in dump[i : i + 16])
        print(f"    0x{i:02X}: {hex_part}")

    # --- Step 3: Test WREN ---
    print("\n[3] Testing Write Enable (WREN):")
    print("    Sending WREN...")
    slave.exchange([OPCODE_WREN])
    status = read_status()
    print(
        f"    Status after WREN: 0x{status:02X} (WEL={'SET' if status & 0x02 else 'NOT SET'})"
    )

    if not (status & 0x02):
        print("\n    *** WEL bit is NOT set! ***")
        print("    Possible causes:")
        print("    - MOSI (AD1 -> SI) is not connected or shorted")
        print("    - CS# (AD3 -> CS#) is not working properly")
        print("    - Chip is not powered or not an AT25010B")
        print()
        print("    Trying WREN with explicit CS control...")

        # Try using exchange with no read (write-only)
        slave.exchange([OPCODE_WREN], readlen=0)
        status = read_status()
        print(
            f"    Status after retry: 0x{status:02X} (WEL={'SET' if status & 0x02 else 'NOT SET'})"
        )

        if not (status & 0x02):
            print("\n    WREN still not working. Check MOSI wiring.")
            print("    Also verify: is this actually an AT25010B (SPI)?")
            print("    (Not an AT24C01 which is I2C and looks similar)")
            ctrl.terminate()
            sys.exit(1)

    # --- Step 4: Try writing a single byte ---
    print("\n[4] Attempting single byte write: 0xAB -> address 0x00")
    slave.exchange([OPCODE_WREN])
    status = read_status()
    print(f"    WEL before write: {'SET' if status & 0x02 else 'NOT SET'}")

    slave.exchange([OPCODE_WRITE, 0x00, 0xAB])
    print("    Write command sent, waiting 10ms...")
    time.sleep(WRITE_CYCLE)

    status = read_status()
    print(
        f"    Status after write: 0x{status:02X} (WIP={status & 0x01}, WEL={bool(status & 0x02)})"
    )

    readback = read_data(0x00, 1)
    print(f"    Readback address 0x00: 0x{readback[0]:02X}")

    if readback[0] == 0xAB:
        print("    *** Single byte write SUCCEEDED! ***")
    elif readback[0] == 0xFF:
        print("    *** Still 0xFF — write is not working ***")
    else:
        print(f"    *** Got unexpected value 0x{readback[0]:02X} ***")

    # --- Step 5: If single byte worked, write the full data ---
    if readback[0] == 0xAB:
        print("\n[5] Writing full data blocks...")

        blocks = [
            (0x00, bytes.fromhex("39558d1f193656ab8b4b65e25ac48474")),
            (0x18, bytes.fromhex("bbe8278a67f960605adafd6f63cf7ba7")),
        ]

        for addr, data in blocks:
            print(f"\n    Writing {len(data)} bytes to 0x{addr:02X}...")
            offset = 0
            while offset < len(data):
                current_addr = addr + offset
                page_offset = current_addr % PAGE_SIZE
                chunk_size = min(PAGE_SIZE - page_offset, len(data) - offset)
                chunk = data[offset : offset + chunk_size]

                slave.exchange([OPCODE_WREN])
                cmd = bytes([OPCODE_WRITE, current_addr & 0xFF]) + chunk
                slave.exchange(cmd)
                time.sleep(WRITE_CYCLE)

                # Wait for WIP to clear
                for _ in range(100):
                    if not (read_status() & 0x01):
                        break
                    time.sleep(0.001)

                offset += chunk_size
                print(
                    f"      Wrote {chunk_size} bytes at 0x{current_addr:02X}: {chunk.hex()}"
                )

            readback = read_data(addr, len(data))
            match = readback == data
            print(f"    Verify: {'PASS' if match else 'FAIL'}")
            if not match:
                print(f"    Expected: {data.hex()}")
                print(f"    Got:      {readback.hex()}")

        print("\n    Final dump:")
        dump = read_data(0x00, 0x28)
        for i in range(0, len(dump), 16):
            hex_part = " ".join(f"{b:02X}" for b in dump[i : i + 16])
            print(f"    0x{i:02X}: {hex_part}")
    else:
        print("\n[5] Skipping full write — single byte test failed.")
        print("\n    Troubleshooting checklist:")
        print("    [ ] MOSI: FT232H AD1 -> AT25010B pin 5 (SI)")
        print("    [ ] MISO: FT232H AD2 -> AT25010B pin 2 (SO)")
        print("    [ ] SCK:  FT232H AD0 -> AT25010B pin 6 (SCK)")
        print("    [ ] CS#:  FT232H AD3 -> AT25010B pin 1 (CS#)")
        print("    [ ] VCC:  3.3V -> AT25010B pin 8 (VCC)")
        print("    [ ] WP#:  3.3V -> AT25010B pin 3 (WP#)")
        print("    [ ] HOLD#:3.3V -> AT25010B pin 7 (HOLD#)")
        print("    [ ] GND:  GND  -> AT25010B pin 4 (GND)")
        print("    [ ] Is this an SPI EEPROM (AT25xxx) not I2C (AT24xxx)?")

    ctrl.terminate()
    print("\nDone.")


if __name__ == "__main__":
    main()
