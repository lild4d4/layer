/**
 * LAYR Guardian — Minimal + SPI Debug
 * Added prints for all MFRC522 SPI communication
 */

#include <Arduino.h>
#include <SPI.h>

#define SS_RFID 9
#define SS_EEPROM 8
#define S_UNLOCK 7

// Registers
#define CommandReg 0x01
#define ComIrqReg 0x04
#define DivIrqReg 0x05
#define ErrorReg 0x06
#define FIFODataReg 0x09
#define FIFOLevelReg 0x0A
#define ControlReg 0x0C
#define BitFramingReg 0x0D
#define CollReg 0x0E
#define ModeReg 0x11
#define TxModeReg 0x12
#define RxModeReg 0x13
#define TxControlReg 0x14
#define TxASKReg 0x15
#define CRCResultRegH 0x21
#define CRCResultRegL 0x22
#define ModWidthReg 0x24
#define TModeReg 0x2A
#define TPrescalerReg 0x2B
#define TReloadRegH 0x2C
#define TReloadRegL 0x2D
#define VersionReg 0x37

// Register names for debug output
const char *getRegName(byte reg) {
  switch (reg) {
  case CommandReg:
    return "CommandReg";
  case ComIrqReg:
    return "ComIrqReg";
  case DivIrqReg:
    return "DivIrqReg";
  case ErrorReg:
    return "ErrorReg";
  case FIFODataReg:
    return "FIFODataReg";
  case FIFOLevelReg:
    return "FIFOLevelReg";
  case ControlReg:
    return "ControlReg";
  case BitFramingReg:
    return "BitFramingReg";
  case CollReg:
    return "CollReg";
  case ModeReg:
    return "ModeReg";
  case TxModeReg:
    return "TxModeReg";
  case RxModeReg:
    return "RxModeReg";
  case TxControlReg:
    return "TxControlReg";
  case TxASKReg:
    return "TxASKReg";
  case CRCResultRegH:
    return "CRCResultRegH";
  case CRCResultRegL:
    return "CRCResultRegL";
  case ModWidthReg:
    return "ModWidthReg";
  case TModeReg:
    return "TModeReg";
  case TPrescalerReg:
    return "TPrescalerReg";
  case TReloadRegH:
    return "TReloadRegH";
  case TReloadRegL:
    return "TReloadRegL";
  case VersionReg:
    return "VersionReg";
  default:
    return "Unknown";
  }
}

struct Uid {
  byte size;
  byte uidByte[10];
  byte sak;
} uid;

uint8_t iBlockPCB = 0x02;

void wrReg(byte reg, byte val) {
  byte addrByte = reg << 1; // Write address format

  Serial.print(F("[SPI-WR] TX: 0x"));
  if (addrByte < 0x10)
    Serial.print("0");
  Serial.print(addrByte, HEX);
  Serial.print(F(" 0x"));
  if (val < 0x10)
    Serial.print("0");
  Serial.print(val, HEX);
  Serial.print(F("  ("));
  Serial.print(getRegName(reg));
  Serial.print(F(" <- 0x"));
  if (val < 0x10)
    Serial.print("0");
  Serial.print(val, HEX);
  Serial.println(F(")"));

  SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));
  digitalWrite(SS_RFID, LOW);
  SPI.transfer(addrByte);
  SPI.transfer(val);
  digitalWrite(SS_RFID, HIGH);
  SPI.endTransaction();
}

byte rdReg(byte reg) {
  byte addrByte = 0x80 | (reg << 1); // Read address format

  SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));
  digitalWrite(SS_RFID, LOW);
  SPI.transfer(addrByte);
  byte v = SPI.transfer(0);
  digitalWrite(SS_RFID, HIGH);
  SPI.endTransaction();

  Serial.print(F("[SPI-RD] TX: 0x"));
  if (addrByte < 0x10)
    Serial.print("0");
  Serial.print(addrByte, HEX);
  Serial.print(F(" 0x00  RX: 0x"));
  if (v < 0x10)
    Serial.print("0");
  Serial.print(v, HEX);
  Serial.print(F("  ("));
  Serial.print(getRegName(reg));
  Serial.print(F(" -> 0x"));
  if (v < 0x10)
    Serial.print("0");
  Serial.print(v, HEX);
  Serial.println(F(")"));

  return v;
}

byte calculateCRC(byte *data, byte length, byte *result) {
  Serial.println(F("--- CRC Calculation Start ---"));
  wrReg(CommandReg, 0x00);
  wrReg(DivIrqReg, 0x04);
  wrReg(FIFOLevelReg, 0x80);

  Serial.print(F("[CRC] Loading FIFO with "));
  Serial.print(length);
  Serial.print(F(" bytes: "));
  for (byte i = 0; i < length; i++) {
    if (data[i] < 0x10)
      Serial.print("0");
    Serial.print(data[i], HEX);
    Serial.print(" ");
    wrReg(FIFODataReg, data[i]);
  }
  Serial.println();

  wrReg(CommandReg, 0x03);
  long t = millis();
  while (millis() - t < 89) {
    if (rdReg(DivIrqReg) & 0x04) {
      wrReg(CommandReg, 0x00);
      result[0] = rdReg(CRCResultRegL);
      result[1] = rdReg(CRCResultRegH);
      Serial.print(F("[CRC] Result: 0x"));
      if (result[0] < 0x10)
        Serial.print("0");
      Serial.print(result[0], HEX);
      Serial.print(F(" 0x"));
      if (result[1] < 0x10)
        Serial.print("0");
      Serial.println(result[1], HEX);
      Serial.println(F("--- CRC Calculation End ---"));
      return 1;
    }
  }
  Serial.println(F("[CRC] TIMEOUT!"));
  Serial.println(F("--- CRC Calculation End ---"));
  return 0;
}

byte PCD_TransceiveData(byte *sendData, byte sendLen, byte *backData,
                        byte *backLen, byte *validBits, byte rxAlign,
                        bool checkCRC) {
  Serial.println(F("=== Transceive Start ==="));
  Serial.print(F("[TX Data] "));
  for (byte i = 0; i < sendLen; i++) {
    if (sendData[i] < 0x10)
      Serial.print("0");
    Serial.print(sendData[i], HEX);
    Serial.print(" ");
  }
  Serial.println();

  wrReg(CommandReg, 0x00);
  wrReg(ComIrqReg, 0x7F);
  wrReg(FIFOLevelReg, 0x80);

  Serial.print(F("[FIFO Load] "));
  for (byte i = 0; i < sendLen; i++) {
    if (sendData[i] < 0x10)
      Serial.print("0");
    Serial.print(sendData[i], HEX);
    Serial.print(" ");
    wrReg(FIFODataReg, sendData[i]);
  }
  Serial.println();

  byte bf = (rxAlign << 4) + (validBits ? *validBits : 0);
  wrReg(BitFramingReg, bf);
  wrReg(CommandReg, 0x0C);                           // Transceive command
  wrReg(BitFramingReg, rdReg(BitFramingReg) | 0x80); // StartSend

  long t = millis();
  while (true) {
    byte n = rdReg(ComIrqReg);
    if (n & 0x30) {
      Serial.println(F("[IRQ] RxIRq/IdleIRq set"));
      break;
    }
    if (n & 0x01) {
      Serial.println(F("[IRQ] TimerIRq - TIMEOUT"));
      Serial.println(F("=== Transceive End (TIMEOUT) ==="));
      return 0;
    }
    if (millis() - t > 150) {
      Serial.println(F("[Transceive] Software timeout!"));
      Serial.println(F("=== Transceive End (SW TIMEOUT) ==="));
      return 0;
    }
  }

  byte errReg = rdReg(ErrorReg);
  if (errReg & 0x13) {
    Serial.print(F("[ERROR] ErrorReg = 0x"));
    Serial.println(errReg, HEX);
    Serial.println(F("=== Transceive End (ERROR) ==="));
    return 0;
  }

  if (backData && backLen) {
    byte n = rdReg(FIFOLevelReg);
    Serial.print(F("[FIFO] "));
    Serial.print(n);
    Serial.println(F(" bytes in FIFO"));

    if (n > *backLen) {
      Serial.println(F("[ERROR] Buffer too small!"));
      Serial.println(F("=== Transceive End (BUFFER) ==="));
      return 0;
    }
    *backLen = n;

    Serial.print(F("[RX Data] "));
    for (byte i = 0; i < n; i++) {
      backData[i] = rdReg(FIFODataReg);
      if (backData[i] < 0x10)
        Serial.print("0");
      Serial.print(backData[i], HEX);
      Serial.print(" ");
    }
    Serial.println();

    if (validBits)
      *validBits = rdReg(ControlReg) & 0x07;
  }

  if (checkCRC) {
    if (*backLen < 2) {
      Serial.println(F("[CRC Check] Not enough data!"));
      return 0;
    }
    byte cb[2];
    if (!calculateCRC(backData, *backLen - 2, cb))
      return 0;
    if (backData[*backLen - 2] != cb[0] || backData[*backLen - 1] != cb[1]) {
      Serial.println(F("[CRC Check] MISMATCH!"));
      return 0;
    }
    Serial.println(F("[CRC Check] OK"));
  }

  Serial.println(F("=== Transceive End (OK) ==="));
  return 1;
}

bool PICC_IsNewCardPresent() {
  Serial.println(F("\n>>> PICC_IsNewCardPresent <<<"));
  wrReg(TxModeReg, 0x00);
  wrReg(RxModeReg, 0x00);
  wrReg(ModWidthReg, 0x26);
  byte buffer[2], bufferSize = sizeof(buffer), cmd = 0x26, validBits = 7;
  if (PCD_TransceiveData(&cmd, 1, buffer, &bufferSize, &validBits, 0, false)) {
    if (bufferSize != 2) {
      Serial.println(F(">>> No card (wrong ATQA size) <<<"));
      return false;
    }
    Serial.print(F(">>> Card detected! ATQA: 0x"));
    Serial.print(buffer[0], HEX);
    Serial.print(F(" 0x"));
    Serial.println(buffer[1], HEX);
    return true;
  }
  Serial.println(F(">>> No card present <<<"));
  return false;
}

bool PICC_ReadCardSerial() {
  Serial.println(F("\n>>> PICC_ReadCardSerial <<<"));
  uid.size = 0;
  wrReg(CollReg, 0x80);

  byte buffer[9] = {0x93, 0x20};
  byte backData[5], backLen = 5;
  Serial.println(F("[Anticollision] Sending 93 20"));
  if (!PCD_TransceiveData(buffer, 2, backData, &backLen, nullptr, 0, false)) {
    Serial.println(F(">>> Anticollision failed <<<"));
    return false;
  }

  Serial.println(F("[Select] Sending 93 70 + UID + CRC"));
  buffer[1] = 0x70;
  buffer[2] = backData[0];
  buffer[3] = backData[1];
  buffer[4] = backData[2];
  buffer[5] = backData[3];
  buffer[6] = backData[4];
  byte crc[2];
  if (!calculateCRC(buffer, 7, crc))
    return false;
  buffer[7] = crc[0];
  buffer[8] = crc[1];

  byte sakBuf[3], sakLen = 3;
  if (!PCD_TransceiveData(buffer, 9, sakBuf, &sakLen, nullptr, 0, false)) {
    Serial.println(F(">>> Select failed <<<"));
    return false;
  }

  uid.size = 4;
  for (byte i = 0; i < 4; i++)
    uid.uidByte[i] = backData[i];
  uid.sak = sakBuf[0];

  Serial.print(F(">>> UID: "));
  for (byte i = 0; i < 4; i++) {
    if (uid.uidByte[i] < 0x10)
      Serial.print("0");
    Serial.print(uid.uidByte[i], HEX);
    Serial.print(" ");
  }
  Serial.print(F(" SAK: 0x"));
  Serial.println(uid.sak, HEX);

  return true;
}

bool sendIBlock(byte *payload, byte payloadLen, byte *response,
                byte *responseLen) {
  Serial.println(F("\n>>> sendIBlock <<<"));
  Serial.print(F("[I-Block PCB] 0x"));
  Serial.println(iBlockPCB, HEX);

  byte frame[payloadLen + 1];
  frame[0] = iBlockPCB;
  memcpy(frame + 1, payload, payloadLen);
  wrReg(FIFOLevelReg, 0x80);
  bool ok = PCD_TransceiveData(frame, sizeof(frame), response, responseLen,
                               nullptr, 0, false) == 1;
  delay(5);
  if (ok) {
    Serial.print(F("[I-Block] PCB toggled to 0x"));
    iBlockPCB ^= 0x01;
    Serial.println(iBlockPCB, HEX);
  }
  return ok;
}

bool doRATS(byte *response, byte *responseLen) {
  Serial.println(F("\n>>> doRATS <<<"));
  byte rats[] = {0xE0, 0x50};
  wrReg(TxModeReg, 0x80);
  wrReg(RxModeReg, 0x00);
  byte status = PCD_TransceiveData(rats, sizeof(rats), response, responseLen,
                                   nullptr, 0, false);
  if (status == 1) {
    wrReg(RxModeReg, 0x80);
    wrReg(BitFramingReg, 0x00);
    wrReg(TModeReg, 0x8D);
    wrReg(TPrescalerReg, 0x3E);
    Serial.print(F(">>> ATS received ("));
    Serial.print(*responseLen);
    Serial.print(F(" bytes): "));
    for (byte i = 0; i < *responseLen; i++) {
      if (response[i] < 0x10)
        Serial.print("0");
      Serial.print(response[i], HEX);
      Serial.print(" ");
    }
    Serial.println();
    return true;
  } else {
    Serial.println(F(">>> RATS failed <<<"));
    return false;
  }
}

void get_EEPROM(byte *buffer, byte length, byte address, byte command) {
  Serial.println(F("\n>>> get_EEPROM <<<"));
  Serial.print(F("[EEPROM] CMD: 0x"));
  Serial.print(command, HEX);
  Serial.print(F(" ADDR: 0x"));
  Serial.println(address, HEX);

  digitalWrite(SS_EEPROM, LOW);
  SPI.transfer(command);
  SPI.transfer(address);
  Serial.print(F("[EEPROM RX] "));
  for (int i = 0; i < 16; i++) {
    buffer[i] = SPI.transfer(address);
    if (buffer[i] < 0x10)
      Serial.print("0");
    Serial.print(buffer[i], HEX);
    Serial.print(" ");
  }
  Serial.println();
  digitalWrite(SS_EEPROM, HIGH);
}

void setup() {
  Serial.begin(115200);
  pinMode(SS_EEPROM, OUTPUT);
  digitalWrite(SS_EEPROM, HIGH);
  pinMode(S_UNLOCK, OUTPUT);
  digitalWrite(S_UNLOCK, LOW);
  delay(3000);

  Serial.println(F("\n\n=================================="));
  Serial.println(F("   LAYR GUARDIAN - DEBUG MODE"));
  Serial.println(F("      + SPI TRACE ENABLED"));
  Serial.println(F("=================================="));

  SPI.begin();
  Serial.println(F("[1] SPI Bus Started"));

  pinMode(SS_RFID, OUTPUT);
  digitalWrite(SS_RFID, HIGH);

  Serial.println(F("\n--- MFRC522 Soft Reset ---"));
  wrReg(CommandReg, 0x0F);
  uint8_t count = 0;
  while (true) {
    delay(50);
    if ((rdReg(CommandReg) & (1 << 4)) == 0)
      break;
    if (++count > 3) {
      Serial.println(F("TIMEOUT: SoftReset failed!"));
      break;
    }
  }

  Serial.println(F("\n--- MFRC522 Init Registers ---"));
  wrReg(TxModeReg, 0x00);
  wrReg(RxModeReg, 0x00);
  wrReg(ModWidthReg, 0x26);
  wrReg(TModeReg, 0x80);
  wrReg(TPrescalerReg, 0xA9);
  wrReg(TReloadRegH, 0x03);
  wrReg(TReloadRegL, 0xE8);
  wrReg(TxASKReg, 0x40);
  wrReg(ModeReg, 0x3D);

  byte tc = rdReg(TxControlReg);
  if ((tc & 0x03) != 0x03)
    wrReg(TxControlReg, tc | 0x03);
  delay(10);

  Serial.print(F("\n[2] Reader Firmware Version: 0x"));
  byte v = rdReg(VersionReg);
  Serial.println(v, HEX);

  if (v == 0x00 || v == 0xFF) {
    Serial.println(F("!!! CRITICAL FAILURE !!!"));
    while (1)
      ;
  }

  Serial.println(F("\n========================================"));
  Serial.println(F("Ready — present card..."));
  Serial.println(F("========================================\n"));
}

void loop() {
  iBlockPCB = 0x02;

  if (!PICC_IsNewCardPresent())
    return;
  if (!PICC_ReadCardSerial())
    return;

  wrReg(TxModeReg, 0x80);

  byte atsBuffer[32], atsLen = sizeof(atsBuffer);
  if (!doRATS(atsBuffer, &atsLen))
    goto halt;

  delay(10);

  {
    Serial.println(F("\n>>> SELECT Application <<<"));
    byte selectCmd[] = {0x00, 0xA4, 0x04, 0x00, 0x06, 0xF0,
                        0x00, 0x00, 0x0C, 0xDC, 0x00};
    byte selectResp[32], selectLen = sizeof(selectResp);

    if (sendIBlock(selectCmd, sizeof(selectCmd), selectResp, &selectLen) != 1) {
      Serial.println(F("FIFO failed"));
      goto halt;
    }

    Serial.print(F("[SELECT Response] "));
    for (byte i = 0; i < selectLen; i++) {
      if (selectResp[i] < 0x10)
        Serial.print("0");
      Serial.print(selectResp[i], HEX);
      Serial.print(" ");
    }
    Serial.println();

    if (selectResp[selectLen - 2] != 0x90 ||
        selectResp[selectLen - 1] != 0x00) {
      Serial.println(F("False Resp"));
      goto halt;
    }

    Serial.println(F("\n>>> GET ID Command <<<"));
    byte getIdCmd[] = {0x80, 0x12, 0x00, 0x00, 0x00};
    byte idRespRFID[32], idLen = sizeof(idRespRFID);

    if (sendIBlock(getIdCmd, sizeof(getIdCmd), idRespRFID, &idLen) != 1)
      goto halt;

    Serial.print(F("\nCard UID: "));
    for (byte i = 0; i < idLen; i++) {
      if (idRespRFID[i] < 0x10)
        Serial.print("0");
      Serial.print(idRespRFID[i], HEX);
      Serial.print(" ");
    }
    Serial.println();

    byte idDataLen = idLen - 3;
    byte idRespEEPROM[16];
    get_EEPROM(idRespEEPROM, 16, 0x00, 0x03);

    Serial.println(F("\n>>> Comparing RFID vs EEPROM <<<"));
    for (byte i = 0; i < 16; i++) {
      Serial.print(F("[Compare] Byte "));
      Serial.print(i);
      Serial.print(F(": RFID=0x"));
      if (idRespRFID[i + 1] < 0x10)
        Serial.print("0");
      Serial.print(idRespRFID[i + 1], HEX);
      Serial.print(F(" EEPROM=0x"));
      if (idRespEEPROM[i] < 0x10)
        Serial.print("0");
      Serial.print(idRespEEPROM[i], HEX);

      if (idRespEEPROM[i] != idRespRFID[i + 1]) {
        Serial.println(F(" <- MISMATCH!"));
        Serial.println(F("\n[ACCESS DENIED]"));
        goto halt;
      }
      Serial.println(F(" OK"));

      if (i == 15) {
        Serial.println(F("\n[ACCESS GRANTED]"));
        Serial.println();
        Serial.println();
        digitalWrite(S_UNLOCK, HIGH);
        delay(5000);
        digitalWrite(S_UNLOCK, LOW);
        goto halt;
      }
    }
  }

halt:
  Serial.println(F("\n--- HALT ---"));
  wrReg(TxModeReg, 0x00);
  delay(2000);
}
