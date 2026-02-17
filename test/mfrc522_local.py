#!/usr/bin/env python3

# python:
# tutorial: https://pimylifeup.com/raspberry-pi-rfid-rc522/
# library : https://github.com/pimylifeup/MFRC522-python/tree/master
#
# arduino:
#   tutorial: https://lastminuteengineers.com/how-rfid-works-rc522-arduino-tutorial/#wiring-an-rc522-rfid-module-to-an-arduino
#   library : https://github.com/miguelbalboa/rfid

import time
from pyftdi.spi import SpiController

# Page 0: Command and status
# 0x00			# reserved for future use
CommandReg = 0x01 << 1  # starts and stops command execution
ComIEnReg = 0x02 << 1  # enable and disable interrupt request control bits
DivIEnReg = 0x03 << 1  # enable and disable interrupt request control bits
ComIrqReg = 0x04 << 1  # interrupt request bits
DivIrqReg = 0x05 << 1  # interrupt request bits
ErrorReg = 0x06 << 1  # error bits showing the error status of the last command executed
Status1Reg = 0x07 << 1  # communication status bits
Status2Reg = 0x08 << 1  # receiver and transmitter status bits
FIFODataReg = 0x09 << 1  # input and output of 64 byte FIFO buffer
FIFOLevelReg = 0x0A << 1  # number of bytes stored in the FIFO buffer
WaterLevelReg = 0x0B << 1  # level for FIFO underflow and overflow warning
ControlReg = 0x0C << 1  # miscellaneous control registers
BitFramingReg = 0x0D << 1  # adjustments for bit-oriented frames
CollReg = (
    0x0E << 1
)  # bit position of the first bit-collision detected on the RF interface
# 0x0F			# reserved for future use

# Page 1: Command
# 						  0x10			# reserved for future use
ModeReg = 0x11 << 1  # defines general modes for transmitting and receiving
TxModeReg = 0x12 << 1  # defines transmission data rate and framing
RxModeReg = 0x13 << 1  # defines reception data rate and framing
TxControlReg = (
    0x14 << 1
)  # controls the logical behavior of the antenna driver pins TX1 and TX2
TxASKReg = 0x15 << 1  # controls the setting of the transmission modulation
TxSelReg = 0x16 << 1  # selects the internal sources for the antenna driver
RxSelReg = 0x17 << 1  # selects internal receiver settings
RxThresholdReg = 0x18 << 1  # selects thresholds for the bit decoder
DemodReg = 0x19 << 1  # defines demodulator settings
# 						  0x1A			# reserved for future use
# 						  0x1B			# reserved for future use
MfTxReg = 0x1C << 1  # controls some MIFARE communication transmit parameters
MfRxReg = 0x1D << 1  # controls some MIFARE communication receive parameters
# 						  0x1E			# reserved for future use
SerialSpeedReg = 0x1F << 1  # selects the speed of the serial UART interface

# Page 2: Configuration
# 						  0x20			# reserved for future use
CRCResultRegH = 0x21 << 1  # shows the MSB and LSB values of the CRC calculation
CRCResultRegL = 0x22 << 1
# 						  0x23			# reserved for future use
ModWidthReg = 0x24 << 1  # controls the ModWidth setting?
# 						  0x25			# reserved for future use
RFCfgReg = 0x26 << 1  # configures the receiver gain
GsNReg = (
    0x27 << 1
)  # selects the conductance of the antenna driver pins TX1 and TX2 for modulation
CWGsPReg = (
    0x28 << 1
)  # defines the conductance of the p-driver output during periods of no modulation
ModGsPReg = (
    0x29 << 1
)  # defines the conductance of the p-driver output during periods of modulation
TModeReg = 0x2A << 1  # defines settings for the internal timer
TPrescalerReg = (
    0x2B << 1
)  # the lower 8 bits of the TPrescaler value. The 4 high bits are in TModeReg.
TReloadRegH = 0x2C << 1  # defines the 16-bit timer reload value
TReloadRegL = 0x2D << 1
TCounterValueRegH = 0x2E << 1  # shows the 16-bit timer value
TCounterValueRegL = 0x2F << 1

# Page 3: Test registers / additional configuration
VersionReg = 0x37 << 1  # shows the software version

# Commands sent to the PICC.
# The commands used by the PCD to manage communication with several PICCs (ISO 14443-3, Type A, section 6.4)
PICC_CMD_REQA = 0x26  # REQuest command, Type A. Invites PICCs in state IDLE to go to READY and prepare for anticollision or selection. 7 bit frame.
PICC_CMD_WUPA = 0x52  # Wake-UP command, Type A. Invites PICCs in state IDLE and HALT to go to READY(*) and prepare for anticollision or selection. 7 bit frame.
PICC_CMD_CT = 0x88  # Cascade Tag. Not really a command, but used during anti collision.
PICC_CMD_SEL_CL1 = 0x93  # Anti collision/Select, Cascade Level 1
PICC_CMD_SEL_CL2 = 0x95  # Anti collision/Select, Cascade Level 2
PICC_CMD_SEL_CL3 = 0x97  # Anti collision/Select, Cascade Level 3
PICC_CMD_HLTA = (
    0x50  # HaLT command, Type A. Instructs an ACTIVE PICC to go to state HALT.
)
PICC_CMD_RATS = (0xE0,)  # Request command for Answer To Reset.
# The commands used for MIFARE Classic (from http:#www.mouser.com/ds/2/302/MF1S503x-89574.pdf, Section 9)
# Use PCD_MFAuthent to authenticate access to a sector, then use these commands to read/write/modify the blocks on the sector.
# The read/write commands can also be used for MIFARE Ultralight.
PICC_CMD_MF_AUTH_KEY_A = 0x60  # Perform authentication with Key A
PICC_CMD_MF_AUTH_KEY_B = 0x61  # Perform authentication with Key B
PICC_CMD_MF_READ = 0x30  # Reads one 16 byte block from the authenticated sector of the PICC. Also used for MIFARE Ultralight.
PICC_CMD_MF_WRITE = 0xA0  # Writes one 16 byte block to the authenticated sector of the PICC. Called "COMPATIBILITY WRITE" for MIFARE Ultralight.
PICC_CMD_MF_DECREMENT = 0xC0  # Decrements the contents of a block and stores the result in the internal data register.
PICC_CMD_MF_INCREMENT = 0xC1  # Increments the contents of a block and stores the result in the internal data register.
PICC_CMD_MF_RESTORE = (
    0xC2  # Reads the contents of a block into the internal data register.
)
PICC_CMD_MF_TRANSFER = (
    0xB0  # Writes the contents of the internal data register to a block.
)
# The commands used for MIFARE Ultralight (from http:#www.nxp.com/documents/data_sheet/MF0ICU1.pdf, Section 8.6)
# The PICC_CMD_MF_READ and PICC_CMD_MF_WRITE can also be used for MIFARE Ultralight.
PICC_CMD_UL_WRITE = 0xA2  # Writes one 4 byte page to the PICC.

# MFRC522 commands. Described in chapter 10 of the datasheet.
PCD_Idle = 0x00  # no action cancels current command execution
PCD_Mem = 0x01  # stores 25 bytes into the internal buffer
PCD_GenerateRandomID = 0x02  # generates a 10-byte random ID number
PCD_CalcCRC = 0x03  # activates the CRC coprocessor or performs a self-test
PCD_Transmit = 0x04  # transmits data from the FIFO buffer
PCD_NoCmdChange = 0x07  # no command change can be used to modify the CommandReg register bits without affecting the command for example the PowerDown bit
PCD_Receive = 0x08  # activates the receiver circuits
PCD_Transceive = 0x0C  # transmits data from FIFO buffer to antenna and automatically activates the receiver after transmission
PCD_MFAuthent = 0x0E  # performs the MIFARE standard authentication as a reader
PCD_SoftReset = 0x0F  # resets the MFRC522

# SPI configuration
SPI_FREQ = 1_000_000  # 1 MHz (safe start)


def millis():
    return int(time.time() * 1000)


class MFRC522:
    def __init__(self) -> None:
        self.spi = SpiController()
        # Create SPI controller
        self.spi.configure("ftdi://ftdi:232h/1")

        # Get SPI port (CS0)
        self.slave = self.spi.get_port(cs=0, freq=SPI_FREQ, mode=0)

    def read_version_string(self):
        version = self.read_register(VersionReg)
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

    def write_register(self, reg, value):
        if isinstance(value, bytes):
            data = [reg] + list(value)
        else:
            data = [reg, value]

        self.slave.exchange(data)

    def read_register(self, reg):
        # MSB == 1 is for reading. LSB is not used in address. Datasheet section 8.1.2.3.
        return self.slave.exchange([0x80 | reg], 1)[
            0
        ]  # Read the value back. Send 0 to stop reading.

    def read_register_bytes(self, reg, length):
        # MSB == 1 is for reading. LSB is not used in address. Datasheet section 8.1.2.3.
        return self.slave.exchange(
            [0x80 | reg], length
        )  # Read the value back. Send 0 to stop reading.

    def clear_register_bit_mask(self, reg, mask):
        tmp = self.read_register(reg)
        self.write_register(reg, tmp & (~mask))

    def set_register_bit_mask(self, reg, mask):
        tmp = self.read_register(reg)
        self.write_register(reg, tmp | mask)

    def antenna_on(self):
        value = self.read_register(TxControlReg)
        if (value & 0x03) != 0x03:
            self.write_register(TxControlReg, value | 0x03)

    def pcd_reset(self):
        self.write_register(CommandReg, PCD_SoftReset)
        time.sleep(0.05)

    def pdc_init(self):
        self.pcd_reset()
        # Reset baud rates
        self.write_register(TxModeReg, 0x00)
        self.write_register(RxModeReg, 0x00)
        # Reset ModWidthReg
        self.write_register(ModWidthReg, 0x26)

        # When communicating with a PICC we need a timeout if something goes wrong.
        # f_timer = 13.56 MHz / (2*TPreScaler+1) where TPreScaler = [TPrescaler_Hi:TPrescaler_Lo].
        # TPrescaler_Hi are the four low bits in TModeReg. TPrescaler_Lo is TPrescalerReg.
        self.write_register(
            TModeReg, 0x80
        )  # TAuto=1 timer starts automatically at the end of the transmission in all communication modes at all speeds
        self.write_register(
            TPrescalerReg, 0xA9
        )  # TPreScaler = TModeReg[3..0]:TPrescalerReg, ie 0x0A9 = 169 => f_timer=40kHz, ie a timer period of 25μs.
        self.write_register(
            TReloadRegH, 0x03
        )  # Reload timer with 0x3E8 = 1000, ie 25ms before timeout.
        self.write_register(TReloadRegL, 0xE8)

        self.write_register(
            TxASKReg, 0x40
        )  # Default 0x00. Force a 100 % ASK modulation independent of the ModGsPReg register setting
        self.write_register(
            ModeReg, 0x3D
        )  # Default 0x3F. Set the preset value for the CRC coprocessor for the CalcCRC command to 0x6363 (ISO 14443-3 part 6.2.4)
        self.antenna_on()  # Enable the antenna driver pins TX1 and TX2 (they were disabled by the reset)
        print("pdc initialized")

    def transceive(
        self,
        sendData,  # Pointer to the data to transfer to the FIFO. Do NOT include the CRC_A.
    ):
        # Transceive the data, store the reply in cmdBuffer[]
        waitIRq = 0x30  # RxIRq and IdleIRq
        (result_status, result, valid_bits) = self.communicate_with_picc(
            PCD_Transceive, sendData, True, 0, waitIRq=waitIRq
        )
        if result_status != "STATUS_OK":
            return result_status

        return result

    def communicate_with_picc(
        self,
        command,  # The command to execute. One of the PCD_Command enums.
        sendData,  # Pointer to the data to transfer to the FIFO.
        retrieveBackData,  # Expected retrieve the data
        validBits,  # In/Out: The number of valid bits in the last byte. 0 for 8 valid bits.
        waitIRq=0x30,  # The bits in the ComIrqReg register that signals successful completion of the command.
    ):
        # Prepare values for BitFramingReg
        txLastBits = validBits if validBits else 0
        bitFraming = txLastBits  # RxAlign = BitFramingReg[6..4]. TxLastBits = BitFramingReg[2..0]

        self.write_register(CommandReg, PCD_Idle)  # Stop any active command.
        self.write_register(ComIrqReg, 0x7F)  # Clear all seven interrupt request bits
        self.write_register(FIFOLevelReg, 0x80)  # FlushBuffer = 1, FIFO initialization
        self.write_register(FIFODataReg, sendData)  # Write sendData to the FIFO
        self.write_register(BitFramingReg, bitFraming)  # Bit adjustments
        self.write_register(CommandReg, command)  # Execute the command
        if command == PCD_Transceive:
            self.set_register_bit_mask(
                BitFramingReg, 0x80
            )  # StartSend=1, transmission of data starts

        # In PCD_Init() we set the TAuto flag in TModeReg. This means the timer
        # automatically starts when the PCD stops transmitting.
        #
        # Wait here for the command to complete. The bits specified in the
        # `waitIRq` parameter define what bits constitute a completed command.
        # When they are set in the ComIrqReg register, then the command is
        # considered complete. If the command is not indicated as complete in
        # ~36ms, then consider the command as timed out.
        deadline = millis() + 36
        completed = False

        while True:
            n = self.read_register(
                ComIrqReg
            )  # ComIrqReg[7..0] bits are: Set1 TxIRq RxIRq IdleIRq HiAlertIRq LoAlertIRq ErrIRq TimerIRq
            # expected.                                 1       1         0          0       0       0
            # got                                 1     1       0         0          1       0       0
            # print("ComIrqReg:", n, waitIRq, n & waitIRq)
            if n & waitIRq:  # One of the interrupts that signal success has been set.
                print("recieved successfully")
                completed = True
                break
            if n & 0x01:  # Timer interrupt - nothing received in 25ms
                return ("STATUS_TIMEOUT", None, 0)
            if millis() > deadline:
                break

        # 36ms and nothing happened. Communication with the MFRC522 might be down.
        if not completed:
            return ("STATUS_TIMEOUT", None, 0)

        # Stop now if any errors except collisions were detected.
        errorRegValue = self.read_register(
            ErrorReg
        )  # ErrorReg[7..0] bits are: WrErr TempErr reserved BufferOvfl CollErr CRCErr ParityErr ProtocolErr
        if errorRegValue & 0x13:  # BufferOvfl ParityErr ProtocolErr
            return ("STATUS_ERROR", None, 0)

        _validBits = 0

        # If the caller wants data back, get it from the MFRC522.
        backData = None
        if retrieveBackData:
            n = self.read_register(FIFOLevelReg)  # Number of bytes in the FIFO
            print("back data lenght", n)
            backData = self.read_register_bytes(
                FIFODataReg, n
            )  # Get received data from FIFO
            _validBits = (
                self.read_register(ControlReg) & 0x07
            )  # RxLastBits[2:0] indicates the number of valid bits in the last received byte. If this value is 000b, the whole byte is valid.

        # Tell about collisions
        if errorRegValue & 0x08:
            return ("STATUS_COLLISION", None, _validBits)

        # Tell about collisions
        if errorRegValue & 0x08:  # CollErr
            return ("STATUS_COLLISION", None, _validBits)

        return ("STATUS_OK", backData, _validBits)

    def is_new_card_present(self):
        # Reset baud rates
        self.write_register(TxModeReg, 0x00)
        self.write_register(RxModeReg, 0x00)
        # Reset ModWidthReg
        self.write_register(ModWidthReg, 0x26)

        status, _, _ = self.req_a()
        print("status new card present:", status)
        return status == "STATUS_OK" or status == "STATUS_COLLISION"

    def req_a(self):
        "check card in field"
        self.clear_register_bit_mask(
            CollReg, 0x80
        )  # ValuesAfterColl=1 => Bits received after collision are cleared.
        validBits = 7  # For REQA and WUPA we need the short frame format - transmit only 7 bits of the last (and only) byte. TxLastBits = BitFramingReg[2..0]
        (status, back_data, validBits) = self.communicate_with_picc(
            command=PCD_Transceive,
            sendData=bytes([PICC_CMD_REQA]),
            retrieveBackData=True,
            validBits=validBits,
        )
        if status != "STATUS_OK":
            return (status, None, 0)

        # ATQA is 2 bytes, and the last received byte must be fully valid.
        if back_data is None or len(back_data) != 2 or validBits != 0:
            return ("STATUS_ERROR", back_data, validBits)

        return ("STATUS_OK", back_data, validBits)


def main():
    mfrc = MFRC522()
    try:
        mfrc.pdc_init()
        mfrc.read_version_string()

        while not mfrc.is_new_card_present():
            time.sleep(1)
        print("new card present")

        mfrc.transceive(
            bytes([0x00, 0xA4, 0x04, 0x00, 0x06, 0xF0, 0x00, 0x00, 0x0C, 0xDC, 0x00])
        )
    except KeyboardInterrupt:
        print("finished running tests")
    finally:
        mfrc.spi.terminate()


if __name__ == "__main__":
    main()
