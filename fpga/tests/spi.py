from pyftdi.spi import SpiController
from pyftdi.usbtools import UsbTools

vps = [
    (0x0403, 0x6014),  # FT232H
]

# List all FTDI devices
for device in UsbTools.find_all(vps):
    print("Device found:")
    print(device)


# Initialize the SPI controller
spi = SpiController()

# Connect to the FT322H (the URL may vary based on your system)
# 'ftdi://ftdi:232h/1' means first interface of FT232H/FT2232H device
spi.configure('ftdi://ftdi:232h/1')

# Get a SPI port (CS0)
slave = spi.get_port(cs=0, freq=1E6, mode=0)  # mode=0 -> CPOL=0, CPHA=0

try:
    prev_data = None
    while True:
        read_data = slave.read(8)
        if read_data != prev_data:
            prev_data = read_data
            print("Data read:", read_data)

except KeyboardInterrupt:
    print("\nCtrl+C detected. Shutting down...")

finally:
    spi.terminate()
    print("SPI terminated cleanly.")
