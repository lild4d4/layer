#!/usr/bin/env python3

from pyftdi.spi import SpiController

# SPI configuration
SPI_FREQ = 1_000_000  # 1 MHz (safe start)

def main():
    # Create SPI controller
    spi = SpiController()
    spi.configure('ftdi://ftdi:232h/1')

    # Get SPI port (CS0)
    slave = spi.get_port(cs=0, freq=SPI_FREQ, mode=0)

    # MFRC522 Version Register
    VERSION_REG = 0x37

    # Construct read address byte
    # Format: 1AAAAAA0
    addr = (VERSION_REG << 1) | 0x80

    # Perform transaction
    # Send address, read 1 byte back
    response = slave.exchange([addr], 1)

    version = response[0]
    for b in bytes(response):
        print(b)

    print(f"MFRC522 Version register: 0x{version:02X}")

    # Known values:
    # 0x91 -> v1.0
    # 0x92 -> v2.0

    if version == 0x91:
        print("Detected MFRC522 v1.0")
    elif version == 0x92:
        print("Detected MFRC522 v2.0")
    else:
        print("Unknown version value")

    spi.terminate()


if __name__ == "__main__":
    main()

