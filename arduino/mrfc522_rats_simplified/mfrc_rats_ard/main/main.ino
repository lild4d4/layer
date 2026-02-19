/**
 * LAYR Guardian — Minimal
 * Exact functionality, shortened form.
 */

#include <Arduino.h>
#include <SPI.h>

#define SS_RFID    9
#define SS_EEPROM  8
#define S_UNLOCK   7

// Registers
#define CommandReg     0x01
#define ComIrqReg      0x04
#define DivIrqReg      0x05
#define ErrorReg       0x06
#define FIFODataReg    0x09
#define FIFOLevelReg   0x0A
#define ControlReg     0x0C
#define BitFramingReg  0x0D
#define CollReg        0x0E
#define ModeReg        0x11
#define TxModeReg      0x12
#define RxModeReg      0x13
#define TxControlReg   0x14
#define TxASKReg       0x15
#define CRCResultRegH  0x21
#define CRCResultRegL  0x22
#define ModWidthReg    0x24
#define TModeReg       0x2A
#define TPrescalerReg  0x2B
#define TReloadRegH    0x2C
#define TReloadRegL    0x2D
#define VersionReg     0x37

struct Uid {
  byte size;
  byte uidByte[10];
  byte sak;
} uid;

uint8_t iBlockPCB = 0x02;
// ──────────────────────────────
// Debug helpers: print all SPI bytes (TX/RX) in a compact hex format.
// Example:
//   TX: 80 A5 F4
//   RX: A6 00 12
// ──────────────────────────────
static void printHex2(uint8_t b) {
  if (b < 0x10) Serial.print('0');
  Serial.print(b, HEX);
}

static void logBytes(const __FlashStringHelper *prefix, const uint8_t *data, size_t len) {
  Serial.print(prefix);
  Serial.print(F(": "));
  for (size_t i = 0; i < len; i++) {
    printHex2(data[i]);
    if (i + 1 < len) Serial.print(' ');
  }
  Serial.println();
}

static void logStep(const __FlashStringHelper *msg) {
  Serial.println();
  Serial.print(F("=== "));
  Serial.print(msg);
  Serial.println(F(" ==="));
}


void wrReg(byte reg, byte val) {
  SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));
  digitalWrite(SS_RFID, LOW);

  // SPI is full duplex: each transmitted byte yields a simultaneously received byte.
  uint8_t tx[2] = { (uint8_t)(reg << 1), (uint8_t)val };
  uint8_t rx[2];
  rx[0] = SPI.transfer(tx[0]);
  rx[1] = SPI.transfer(tx[1]);

  digitalWrite(SS_RFID, HIGH);
  SPI.endTransaction();

  logBytes(F("TX"), tx, sizeof(tx));
  logBytes(F("RX"), rx, sizeof(rx));
}

byte rdReg(byte reg) {
  SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));
  digitalWrite(SS_RFID, LOW);

  uint8_t tx[2] = { (uint8_t)(0x80 | (reg << 1)), 0x00 };
  uint8_t rx[2];
  rx[0] = SPI.transfer(tx[0]);
  rx[1] = SPI.transfer(tx[1]);

  digitalWrite(SS_RFID, HIGH);
  SPI.endTransaction();

  logBytes(F("TX"), tx, sizeof(tx));
  logBytes(F("RX"), rx, sizeof(rx));

  return rx[1];
}

byte calculateCRC(byte *data, byte length, byte *result) {
  wrReg(CommandReg, 0x00);
  wrReg(DivIrqReg, 0x04);
  wrReg(FIFOLevelReg, 0x80);
  for (byte i = 0; i < length; i++) wrReg(FIFODataReg, data[i]);
  wrReg(CommandReg, 0x03);
  long t = millis();
  while (millis() - t < 89) {
    if (rdReg(DivIrqReg) & 0x04) {
      wrReg(CommandReg, 0x00);
      result[0] = rdReg(CRCResultRegL);
      result[1] = rdReg(CRCResultRegH);
      return 1;
    }
  }
  return 0;
}

byte PCD_TransceiveData(byte *sendData, byte sendLen,
                        byte *backData, byte *backLen,
                        byte *validBits, byte rxAlign,
                        bool checkCRC) {
  wrReg(CommandReg, 0x00);
  wrReg(ComIrqReg, 0x7F);
  wrReg(FIFOLevelReg, 0x80);
  for (byte i = 0; i < sendLen; i++) wrReg(FIFODataReg, sendData[i]);
  byte bf = (rxAlign << 4) + (validBits ? *validBits : 0);
  wrReg(BitFramingReg, bf);
  wrReg(CommandReg, 0x0C);
  wrReg(BitFramingReg, rdReg(BitFramingReg) | 0x80);

  long t = millis();
  while (true) {
    byte n = rdReg(ComIrqReg);
    if (n & 0x30) break;
    if (n & 0x01) return 0;
    if (millis() - t > 150) return 0;
  }
  if (rdReg(ErrorReg) & 0x13) return 0;

  if (backData && backLen) {
    byte n = rdReg(FIFOLevelReg);
    if (n > *backLen) return 0;
    *backLen = n;
    for (byte i = 0; i < n; i++) backData[i] = rdReg(FIFODataReg);
    if (validBits) *validBits = rdReg(ControlReg) & 0x07;
  }

  if (checkCRC) {
    if (*backLen < 2) return 0;
    byte cb[2];
    if (!calculateCRC(backData, *backLen - 2, cb)) return 0;
    if (backData[*backLen - 2] != cb[0] || backData[*backLen - 1] != cb[1]) return 0;
  }
  return 1;
}

bool PICC_IsNewCardPresent() {
  logStep(F("Configure MFRC522"));
  wrReg(TxModeReg, 0x00);
  wrReg(RxModeReg, 0x00);
  wrReg(ModWidthReg, 0x26);
  byte buffer[2], bufferSize = sizeof(buffer), cmd = 0x26, validBits = 7;
  if (PCD_TransceiveData(&cmd, 1, buffer, &bufferSize, &validBits, 0, false)) {
    if (bufferSize != 2) return false;
    return true;
  }
  return false;
}

bool PICC_ReadCardSerial() {
  uid.size = 0;
  wrReg(CollReg, 0x80);

  byte buffer[9] = {0x93, 0x20};
  byte backData[5], backLen = 5;
  if (!PCD_TransceiveData(buffer, 2, backData, &backLen, nullptr, 0, false)) return false;

  buffer[1] = 0x70;
  buffer[2] = backData[0];
  buffer[3] = backData[1];
  buffer[4] = backData[2];
  buffer[5] = backData[3];
  buffer[6] = backData[4];
  byte crc[2];
  if (!calculateCRC(buffer, 7, crc)) return false;
  buffer[7] = crc[0];
  buffer[8] = crc[1];

  byte sakBuf[3], sakLen = 3;
  if (!PCD_TransceiveData(buffer, 9, sakBuf, &sakLen, nullptr, 0, false)) return false;

  uid.size = 4;
  for (byte i = 0; i < 4; i++) uid.uidByte[i] = backData[i];
  uid.sak = sakBuf[0];
  return true;
}

bool sendIBlock(byte *payload, byte payloadLen, byte *response, byte *responseLen) {
  byte frame[payloadLen + 1];
  frame[0] = iBlockPCB;
  memcpy(frame + 1, payload, payloadLen);

  logStep(F("I-Block exchange"));
  logBytes(F("TX"), frame, sizeof(frame));

  wrReg(FIFOLevelReg, 0x80);
  bool ok = PCD_TransceiveData(frame, sizeof(frame), response, responseLen, nullptr, 0, false) == 1;

  if (ok) {
    logBytes(F("RX"), response, (size_t)(*responseLen));
  } else {
    Serial.println(F("I-Block exchange failed"));
  }

  delay(5);
  if (ok) iBlockPCB ^= 0x01;
  return ok;
}

bool doRATS(byte *response, byte *responseLen) {
  byte rats[] = {0xE0, 0x50};

  logStep(F("RATS"));
  logBytes(F("TX"), rats, sizeof(rats));

  wrReg(TxModeReg, 0x80);
  wrReg(RxModeReg, 0x00);
  byte status = PCD_TransceiveData(rats, sizeof(rats), response, responseLen, nullptr, 0, false);

  if (status == 1) {
    logBytes(F("RX"), response, (size_t)(*responseLen));
    wrReg(RxModeReg, 0x80);
    wrReg(BitFramingReg, 0x00);
    wrReg(TModeReg, 0x8D);
    wrReg(TPrescalerReg, 0x3E);
    return true;
  } else {
    Serial.println(F("RATS failed"));
    return false;
  }
}

void get_EEPROM(byte *buffer, byte length, byte address, byte command) {
  SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));
  digitalWrite(SS_EEPROM, LOW);

  // Typical EEPROM read: [CMD][ADDR][dummy ...] while shifting out data.
  // We log every byte on the wire.
  const size_t tx_len = 2 + length;
  uint8_t tx[2 + 32];  // length used in this sketch is small (<= 32)
  uint8_t rx[2 + 32];

  tx[0] = (uint8_t)command;
  tx[1] = (uint8_t)address;
  for (byte i = 0; i < length; i++) tx[2 + i] = 0x00;

  for (size_t i = 0; i < tx_len; i++) rx[i] = SPI.transfer(tx[i]);

  // Data usually starts after the command+address phase.
  for (byte i = 0; i < length; i++) buffer[i] = rx[2 + i];

  digitalWrite(SS_EEPROM, HIGH);
  SPI.endTransaction();

  logBytes(F("TX"), tx, tx_len);
  logBytes(F("RX"), rx, tx_len);
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
  Serial.println(F("=================================="));

  logStep(F("SPI init"));
  SPI.begin();
  Serial.println(F("[1] SPI Bus Started"));

  pinMode(SS_RFID, OUTPUT);
  digitalWrite(SS_RFID, HIGH);

  logStep(F("MFRC522 soft reset"));
  wrReg(CommandReg, 0x0F);
  uint8_t count = 0;
  while (true) {
    delay(50);
    if ((rdReg(CommandReg) & (1 << 4)) == 0) break;
    if (++count > 3) { Serial.println(F("TIMEOUT: SoftReset failed!")); break; }
  }

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
  if ((tc & 0x03) != 0x03) wrReg(TxControlReg, tc | 0x03);
  delay(10);

  logStep(F("Read VersionReg"));
  Serial.print(F("[2] Reader Firmware Version: 0x"));
  byte v = rdReg(VersionReg);
  Serial.println(v, HEX);

  if (v == 0x00 || v == 0xFF) {
    Serial.println(F("!!! CRITICAL FAILURE !!!"));
    while(1);
  }

  Serial.println(F("Ready — present card..."));
}

void loop() {
  iBlockPCB = 0x02;

  if (!PICC_IsNewCardPresent()) return;
  if (!PICC_ReadCardSerial()) return;

  logStep(F("Card present"));

  wrReg(TxModeReg, 0x80);

  byte atsBuffer[32], atsLen = sizeof(atsBuffer);
  if (!doRATS(atsBuffer, &atsLen)) goto halt;
  
  delay(10);

  {
    logStep(F("Select application"));
    byte selectCmd[] = {0x00,0xA4,0x04,0x00,0x06, 0xF0,0x00,0x00,0x0C,0xDC,0x00};
    byte selectResp[32], selectLen = sizeof(selectResp);

    if (sendIBlock(selectCmd, sizeof(selectCmd), selectResp, &selectLen) != 1) {
      Serial.println(F("FIFO failed"));
      goto halt;
    }

    if (selectResp[selectLen - 2] != 0x90 || selectResp[selectLen - 1] != 0x00) {
      Serial.println(F("False Resp"));
      goto halt;
    }

    logStep(F("Get card UID"));
    byte getIdCmd[] = {0x80,0x12,0x00,0x00,0x00};
    byte idRespRFID[32], idLen = sizeof(idRespRFID);

    if (sendIBlock(getIdCmd, sizeof(getIdCmd), idRespRFID, &idLen) != 1) goto halt;

    Serial.print(F("\nCard UID: "));
    for (byte i = 0; i < idLen; i++) { Serial.print(idRespRFID[i], HEX); Serial.print(" "); }
    Serial.println();

    byte idDataLen = idLen - 3;
    byte idRespEEPROM[16];
    logStep(F("Read EEPROM UID"));
    get_EEPROM(idRespEEPROM, 16, 0x00, 0x03);

    logStep(F("Compare UID"));
    for (byte i = 0; i < 16; i++) {
      if (idRespEEPROM[i] != idRespRFID[i + 1]) {
        Serial.println(F("\n[ACCESS DENIED]"));
        goto halt;
      } 
    
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
  wrReg(TxModeReg, 0x00);
  delay(2000);
}