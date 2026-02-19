#!/usr/bin/env python3
"""
LAYR Guardian — FT232H Version
Exact functionality port from Arduino, using pyftdi.spi
"""

import time
from pyftdi.spi import SpiController

# MFRC522 Registers
CommandReg = 0x01
ComIrqReg = 0x04
DivIrqReg = 0x05
ErrorReg = 0x06
FIFODataReg = 0x09
FIFOLevelReg = 0x0A
ControlReg = 0x0C
BitFramingReg = 0x0D
CollReg = 0x0E
ModeReg = 0x11
TxModeReg = 0x12
RxModeReg = 0x13
TxControlReg = 0x14
TxASKReg = 0x15
CRCResultRegH = 0x21
CRCResultRegL = 0x22
ModWidthReg = 0x24
TModeReg = 0x2A
TPrescalerReg = 0x2B
TReloadRegH = 0x2C
TReloadRegL = 0x2D
VersionReg = 0x37

SPI_FREQ = 100_000  # 1 MHz (safe start)


class Uid:
    def __init__(self):
        self.size = 0
        self.uid_byte = [0] * 10
        self.sak = 0


class LAYRGuardian:
    def __init__(self, ftdi_url="ftdi://ftdi:232h/1"):
        self.uid = Uid()
        self.i_block_pcb = 0x02

        # Initialize SPI controller
        self.spi = SpiController()
        self.spi.configure(ftdi_url)
        self.slave = self.spi.get_port(cs=0, freq=SPI_FREQ, mode=0)

    def print_hex(self, b):
        """Print a single byte in hex format"""
        return f"{b:02X}"

    def print_hex_buf(self, data):
        """Print a buffer of bytes in hex format"""
        return " ".join(self.print_hex(b) for b in data)

    def wr_reg(self, reg, val):
        """Write a value to an MFRC522 register"""
        tx_addr = reg << 1
        print(f"SPI TX: {self.print_hex(tx_addr)} {self.print_hex(val)}")
        self.slave.exchange([tx_addr, val])

    def rd_reg(self, reg):
        """Read a value from an MFRC522 register"""
        tx_addr = 0x80 | (reg << 1)
        print(f"SPI TX: {self.print_hex(tx_addr)} 00")
        result = self.slave.exchange([tx_addr, 0x00], duplex=True)
        return result[1]

    def calculate_crc(self, data):
        """Calculate CRC using the MFRC522's internal CRC coprocessor"""
        self.wr_reg(CommandReg, 0x00)
        self.wr_reg(DivIrqReg, 0x04)
        self.wr_reg(FIFOLevelReg, 0x80)

        for byte in data:
            self.wr_reg(FIFODataReg, byte)

        self.wr_reg(CommandReg, 0x03)

        start_time = time.time()
        while (time.time() - start_time) < 0.089:
            if self.rd_reg(DivIrqReg) & 0x04:
                self.wr_reg(CommandReg, 0x00)
                result = [self.rd_reg(CRCResultRegL), self.rd_reg(CRCResultRegH)]
                return result
        return None

    def pcd_transceive_data(
        self, send_data, back_len_max, valid_bits=None, rx_align=0, check_crc=False
    ):
        """
        Transceive data with the PICC
        Returns: (success, back_data, valid_bits) or (False, None, None)
        """
        self.wr_reg(CommandReg, 0x00)
        self.wr_reg(ComIrqReg, 0x7F)
        self.wr_reg(FIFOLevelReg, 0x80)

        for byte in send_data:
            self.wr_reg(FIFODataReg, byte)

        bf = (rx_align << 4) + (valid_bits if valid_bits else 0)
        self.wr_reg(BitFramingReg, bf)
        self.wr_reg(CommandReg, 0x0C)

        # Start transmission
        current_bf = self.rd_reg(BitFramingReg)
        self.wr_reg(BitFramingReg, current_bf | 0x80)

        start_time = time.time()
        while True:
            n = self.rd_reg(ComIrqReg)
            if n & 0x30:
                break
            if n & 0x01:
                return False, None, None
            if (time.time() - start_time) > 0.150:
                return False, None, None

        if self.rd_reg(ErrorReg) & 0x13:
            return False, None, None

        # Read data from FIFO
        n = self.rd_reg(FIFOLevelReg)
        if n > back_len_max:
            return False, None, None

        back_data = []
        for _ in range(n):
            back_data.append(self.rd_reg(FIFODataReg))

        ret_valid_bits = self.rd_reg(ControlReg) & 0x07

        if check_crc:
            if len(back_data) < 2:
                return False, None, None
            cb = self.calculate_crc(back_data[:-2])
            if cb is None:
                return False, None, None
            if back_data[-2] != cb[0] or back_data[-1] != cb[1]:
                return False, None, None

        return True, back_data, ret_valid_bits

    def picc_is_new_card_present(self):
        """Check if a new card is present in the RF field"""
        self.wr_reg(TxModeReg, 0x00)
        self.wr_reg(RxModeReg, 0x00)
        self.wr_reg(ModWidthReg, 0x26)

        cmd = [0x26]
        success, buffer, _ = self.pcd_transceive_data(cmd, 2, valid_bits=7)

        if success and buffer and len(buffer) == 2:
            return True
        return False

    def picc_read_card_serial(self):
        """Read the card's UID"""
        self.uid.size = 0
        self.wr_reg(CollReg, 0x80)

        # Anticollision command
        buffer = [0x93, 0x20]
        success, back_data, _ = self.pcd_transceive_data(buffer, 5)
        if not success or not back_data:
            return False

        # Select command
        select_buffer = [0x93, 0x70] + back_data
        crc = self.calculate_crc(select_buffer)
        if crc is None:
            return False
        select_buffer.extend(crc)

        success, sak_buf, _ = self.pcd_transceive_data(select_buffer, 3)
        if not success or not sak_buf:
            return False

        self.uid.size = 4
        for i in range(4):
            self.uid.uid_byte[i] = back_data[i]
        self.uid.sak = sak_buf[0]
        return True

    def send_i_block(self, payload):
        """Send an I-Block to the PICC"""
        frame = [self.i_block_pcb] + list(payload)
        self.wr_reg(FIFOLevelReg, 0x80)

        success, response, _ = self.pcd_transceive_data(frame, 32)
        time.sleep(0.005)

        if success:
            self.i_block_pcb ^= 0x01
        return success, response

    def do_rats(self):
        """Request Answer To Select (RATS) for ISO 14443-4"""
        rats = [0xE0, 0x50]
        self.wr_reg(TxModeReg, 0x80)
        self.wr_reg(RxModeReg, 0x00)

        success, response, _ = self.pcd_transceive_data(rats, 32)

        if success:
            self.wr_reg(RxModeReg, 0x80)
            self.wr_reg(BitFramingReg, 0x00)
            self.wr_reg(TModeReg, 0x8D)
            self.wr_reg(TPrescalerReg, 0x3E)
            return True, response
        return False, None

    def get_eeprom(self, length, address, command):
        """Read data from EEPROM via SPI (MOCKED)"""
        # TODO: Implement actual EEPROM reading
        return [0x00] * length  # Return mock data

    def set_unlock(self, state):
        """Set the unlock GPIO pin state (MOCKED)"""
        # TODO: Implement actual GPIO control
        print(f"[GPIO] Unlock = {'HIGH' if state else 'LOW'}")

    def setup(self):
        """Initialize the RFID reader"""
        print("\n\n==================================")
        print("   LAYR GUARDIAN - DEBUG MODE")
        print("==================================")
        print("[1] SPI Bus Started")

        # Soft reset
        self.wr_reg(CommandReg, 0x0F)
        count = 0
        while True:
            time.sleep(0.050)
            if (self.rd_reg(CommandReg) & (1 << 4)) == 0:
                break
            count += 1
            if count > 3:
                print("TIMEOUT: SoftReset failed!")
                break

        # Configure registers
        self.wr_reg(TxModeReg, 0x00)
        self.wr_reg(RxModeReg, 0x00)
        self.wr_reg(ModWidthReg, 0x26)
        self.wr_reg(TModeReg, 0x80)
        self.wr_reg(TPrescalerReg, 0xA9)
        self.wr_reg(TReloadRegH, 0x03)
        self.wr_reg(TReloadRegL, 0xE8)
        self.wr_reg(TxASKReg, 0x40)
        self.wr_reg(ModeReg, 0x3D)

        # Turn on antenna
        tc = self.rd_reg(TxControlReg)
        if (tc & 0x03) != 0x03:
            self.wr_reg(TxControlReg, tc | 0x03)
        time.sleep(0.010)

        # Check firmware version
        v = self.rd_reg(VersionReg)
        print(f"[2] Reader Firmware Version: 0x{v:02X}")

        if v == 0x00 or v == 0xFF:
            print("!!! CRITICAL FAILURE !!!")
            return False

        print("Ready — present card...")
        return True

    def loop(self):
        """Main loop iteration"""
        self.i_block_pcb = 0x02

        if not self.picc_is_new_card_present():
            return

        if not self.picc_read_card_serial():
            return

        self.wr_reg(TxModeReg, 0x80)

        # Do RATS
        success, ats_buffer = self.do_rats()
        if not success:
            self.halt()
            return

        time.sleep(0.010)

        # Select application
        select_cmd = [0x00, 0xA4, 0x04, 0x00, 0x06, 0xF0, 0x00, 0x00, 0x0C, 0xDC, 0x00]
        success, select_resp = self.send_i_block(select_cmd)

        if not success:
            print("FIFO failed")
            self.halt()
            return

        if select_resp[-2] != 0x90 or select_resp[-1] != 0x00:
            print("False Resp")
            self.halt()
            return

        # Get ID from card
        get_id_cmd = [0x80, 0x12, 0x00, 0x00, 0x00]
        success, id_resp_rfid = self.send_i_block(get_id_cmd)

        if not success:
            self.halt()
            return

        print(f"\nCard UID: {self.print_hex_buf(id_resp_rfid)}")

        # Compare with EEPROM
        id_resp_eeprom = self.get_eeprom(16, 0x00, 0x03)

        access_granted = True
        for i in range(16):
            if id_resp_eeprom[i] != id_resp_rfid[i + 1]:
                print("\n[ACCESS DENIED]")
                access_granted = False
                break

        if access_granted:
            print("\n[ACCESS GRANTED]")
            print()
            print()
            self.set_unlock(True)
            time.sleep(5.0)
            self.set_unlock(False)

        self.halt()

    def halt(self):
        """Reset reader state"""
        self.wr_reg(TxModeReg, 0x00)
        time.sleep(2.0)

    def run(self):
        """Main entry point"""
        if not self.setup():
            return

        try:
            while True:
                self.loop()
        except KeyboardInterrupt:
            print("\nShutting down...")
            self.set_unlock(False)


def main():
    ftdi_url = "ftdi://ftdi:232h/1"

    print("Initializing LAYR Guardian with FT232H...")
    time.sleep(3.0)  # Match Arduino startup delay

    guardian = LAYRGuardian(ftdi_url)
    guardian.run()


if __name__ == "__main__":
    main()
