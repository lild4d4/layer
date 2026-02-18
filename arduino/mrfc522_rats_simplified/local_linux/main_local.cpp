/**
 * LAYR Guardian — Local Linux byte-level SPI trace
 * Compiles with: g++ -o main main.cpp
 */

#include <cstdio>
#include <cstdint>
#include <cstring>

typedef uint8_t byte;

#define COMMENTS 1

#define EXPECTED_ID { 0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08, \
                      0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F,0x10 }

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

// --- Simulated MFRC522 state ---
static byte regs[0x40];
static byte fifo[64], fifo_len, fifo_rd;
static int transceive_stage = 0;

static void fifo_flush() { fifo_len = 0; fifo_rd = 0; }
static void fifo_push(byte b) { if (fifo_len < 64) fifo[fifo_len++] = b; }
static byte fifo_pop()  { return fifo_rd < fifo_len ? fifo[fifo_rd++] : 0; }

static void sim_prepare_response() {
  byte expected[] = EXPECTED_ID;
  byte r[64]; byte len = 0;
  switch (transceive_stage) {
    case 0: len=2; r[0]=0x04; r[1]=0x00; break;                          // ATQA
    case 1: len=5; r[0]=0xDE; r[1]=0xAD; r[2]=0xBE; r[3]=0xEF;          // UID+BCC
             r[4]=0xDE^0xAD^0xBE^0xEF; break;
    case 2: len=3; r[0]=0x20; r[1]=0xAA; r[2]=0x55; break;              // SAK
    case 3: len=5; r[0]=0x05; r[1]=0x78; r[2]=0x80; r[3]=0x70;          // ATS
             r[4]=0x02; break;
    case 4: len=3; r[0]=0x02; r[1]=0x90; r[2]=0x00; break;              // SELECT APP resp
    case 5: len=1+16+2; r[0]=0x03; memcpy(r+1,expected,16);             // GET_ID resp
             r[17]=0x90; r[18]=0x00; break;
  }
  transceive_stage++;
  fifo_flush();
  for (byte i = 0; i < len; i++) fifo_push(r[i]);
  regs[FIFOLevelReg] = len;
  regs[ComIrqReg] = 0x30;
  regs[ErrorReg] = 0x00;
}

static void sim_init() {
  memset(regs, 0, sizeof(regs));
  regs[VersionReg] = 0x92;
  regs[DivIrqReg]  = 0x04;
  regs[CRCResultRegL] = 0xAA;
  regs[CRCResultRegH] = 0x55;
  fifo_flush();
  transceive_stage = 0;
}

// --- SPI byte output ---

struct Uid {
  byte size;
  byte uidByte[10];
  byte sak;
} uid;

uint8_t iBlockPCB = 0x02;

void wrReg(byte reg, byte val) {
  byte addr = (byte)(reg << 1);
#if COMMENTS
  printf("  // write reg 0x%02X = 0x%02X\n", reg, val);
#endif
  printf("Master: %02X %02X\n", addr, val);
  printf("MFRC  : 00 00\n");

  regs[reg] = val;
  if (reg == FIFOLevelReg && val == 0x80) fifo_flush();
  if (reg == FIFODataReg) fifo_push(val);
  if (reg == CommandReg && val == 0x0C) { // Transceive
#if COMMENTS
    printf("  // Transceive → card responds\n");
#endif
    sim_prepare_response();
  }
  if (reg == CommandReg && val == 0x03) { // CalcCRC
    regs[DivIrqReg] = 0x04;
  }
  if (reg == CommandReg && val == 0x0F) { // SoftReset
    regs[CommandReg] = 0x00;
  }
}

byte rdReg(byte reg) {
  byte addr = (byte)(0x80 | (reg << 1));
  byte val;
  if (reg == FIFODataReg) {
    val = fifo_pop();
    regs[FIFOLevelReg] = fifo_len - fifo_rd;
  } else {
    val = regs[reg];
  }
#if COMMENTS
  printf("  // read reg 0x%02X → 0x%02X\n", reg, val);
#endif
  printf("Master: %02X 00\n", addr);
  printf("MFRC  : 00 %02X\n", val);
  return val;
}

byte calculateCRC(byte *data, byte length, byte *result) {
#if COMMENTS
  printf("  // calculateCRC (%d bytes)\n", length);
#endif
  wrReg(CommandReg, 0x00);
  wrReg(DivIrqReg, 0x04);
  wrReg(FIFOLevelReg, 0x80);
  for (byte i = 0; i < length; i++) wrReg(FIFODataReg, data[i]);
  wrReg(CommandReg, 0x03);
#if COMMENTS
  printf("  // POLLING DivIrqReg for CRC ready\n");
#endif
  if (rdReg(DivIrqReg) & 0x04) {
    wrReg(CommandReg, 0x00);
    result[0] = rdReg(CRCResultRegL);
    result[1] = rdReg(CRCResultRegH);
    return 1;
  }
  return 0;
}

byte PCD_TransceiveData(byte *sendData, byte sendLen,
                        byte *backData, byte *backLen,
                        byte *validBits, byte rxAlign,
                        bool checkCRC) {
#if COMMENTS
  printf("  // PCD_TransceiveData (send %d bytes)\n", sendLen);
#endif
  wrReg(CommandReg, 0x00);
  wrReg(ComIrqReg, 0x7F);
  wrReg(FIFOLevelReg, 0x80);
  for (byte i = 0; i < sendLen; i++) wrReg(FIFODataReg, sendData[i]);
  byte bf = (rxAlign << 4) + (validBits ? *validBits : 0);
  wrReg(BitFramingReg, bf);
  wrReg(CommandReg, 0x0C);
  wrReg(BitFramingReg, rdReg(BitFramingReg) | 0x80);

#if COMMENTS
  printf("  // POLLING ComIrqReg for Rx/Idle/Timeout\n");
#endif
  byte n = rdReg(ComIrqReg);
  if (!(n & 0x30)) return 0;
  if (rdReg(ErrorReg) & 0x13) return 0;

  if (backData && backLen) {
    byte cnt = rdReg(FIFOLevelReg);
    if (cnt > *backLen) return 0;
    *backLen = cnt;
    for (byte i = 0; i < cnt; i++) backData[i] = rdReg(FIFODataReg);
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
#if COMMENTS
  printf("\n  // --- PICC_IsNewCardPresent (REQA) ---\n");
#endif
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
#if COMMENTS
  printf("\n  // --- PICC_ReadCardSerial (Anticoll+Select) ---\n");
#endif
  uid.size = 0;
  wrReg(CollReg, 0x80);

  byte buffer[9] = {0x93, 0x20};
  byte backData[5], backLen = 5;
  if (!PCD_TransceiveData(buffer, 2, backData, &backLen, nullptr, 0, false)) return false;

  buffer[1] = 0x70;
  buffer[2] = backData[0]; buffer[3] = backData[1];
  buffer[4] = backData[2]; buffer[5] = backData[3];
  buffer[6] = backData[4];
  byte crc[2];
  if (!calculateCRC(buffer, 7, crc)) return false;
  buffer[7] = crc[0]; buffer[8] = crc[1];

  byte sakBuf[3], sakLen = 3;
  if (!PCD_TransceiveData(buffer, 9, sakBuf, &sakLen, nullptr, 0, false)) return false;

  uid.size = 4;
  for (byte i = 0; i < 4; i++) uid.uidByte[i] = backData[i];
  uid.sak = sakBuf[0];
  return true;
}

bool sendIBlock(byte *payload, byte payloadLen, byte *response, byte *responseLen) {
#if COMMENTS
  printf("\n  // --- sendIBlock (PCB=0x%02X, %d bytes) ---\n", iBlockPCB, payloadLen);
#endif
  byte frame[payloadLen + 1];
  frame[0] = iBlockPCB;
  memcpy(frame + 1, payload, payloadLen);
  wrReg(FIFOLevelReg, 0x80);
  bool ok = PCD_TransceiveData(frame, payloadLen + 1, response, responseLen, nullptr, 0, false) == 1;
  if (ok) iBlockPCB ^= 0x01;
  return ok;
}

bool doRATS(byte *response, byte *responseLen) {
#if COMMENTS
  printf("\n  // --- doRATS ---\n");
#endif
  byte rats[] = {0xE0, 0x50};
  wrReg(TxModeReg, 0x80);
  wrReg(RxModeReg, 0x00);
  byte status = PCD_TransceiveData(rats, sizeof(rats), response, responseLen, nullptr, 0, false);
  if (status == 1) {
    wrReg(RxModeReg, 0x80);
    wrReg(BitFramingReg, 0x00);
    wrReg(TModeReg, 0x8D);
    wrReg(TPrescalerReg, 0x3E);
    return true;
  }
  return false;
}

void setup() {
  sim_init();

  printf("\n\n==================================\n");
  printf("   LAYR GUARDIAN - DEBUG MODE\n");
  printf("==================================\n\n");

#if COMMENTS
  printf("  // SoftReset\n");
#endif
  wrReg(CommandReg, 0x0F);
#if COMMENTS
  printf("  // POLLING CommandReg for reset complete\n");
#endif
  for (uint8_t count = 0; count < 4; count++) {
    if ((rdReg(CommandReg) & (1 << 4)) == 0) break;
    if (count >= 3) { printf("TIMEOUT: SoftReset failed!\n"); break; }
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

  byte v = rdReg(VersionReg);
  printf("[2] Reader Firmware Version: 0x%02X\n", v);
  if (v == 0x00 || v == 0xFF) { printf("!!! CRITICAL FAILURE !!!\n"); return; }
  printf("Ready — present card...\n\n");
}

void loop() {
  iBlockPCB = 0x02;

  if (!PICC_IsNewCardPresent()) { printf("No card.\n"); return; }
  if (!PICC_ReadCardSerial()) { printf("Read serial failed.\n"); return; }

  wrReg(TxModeReg, 0x80);

  byte atsBuffer[32], atsLen = sizeof(atsBuffer);
  if (!doRATS(atsBuffer, &atsLen)) goto halt;

  {
#if COMMENTS
    printf("\n  // --- SELECT APPLICATION ---\n");
#endif
    byte selectCmd[] = {0x00,0xA4,0x04,0x00,0x06, 0xF0,0x00,0x00,0x0C,0xDC,0x00};
    byte selectResp[32], selectLen = sizeof(selectResp);

    if (!sendIBlock(selectCmd, sizeof(selectCmd), selectResp, &selectLen)) {
      printf("FIFO failed\n"); goto halt;
    }
    if (selectResp[selectLen - 2] != 0x90 || selectResp[selectLen - 1] != 0x00) {
      printf("False Resp\n"); goto halt;
    }

#if COMMENTS
    printf("\n  // --- GET ID ---\n");
#endif
    byte getIdCmd[] = {0x80,0x12,0x00,0x00,0x00};
    byte idRespRFID[32], idLen = sizeof(idRespRFID);

    if (!sendIBlock(getIdCmd, sizeof(getIdCmd), idRespRFID, &idLen)) goto halt;

    printf("\nCard ID: ");
    for (byte i = 0; i < idLen; i++) printf("%02X ", idRespRFID[i]);
    printf("\n");

    byte expected[] = EXPECTED_ID;
#if COMMENTS
    printf("  // Compare card ID against EXPECTED_ID\n");
#endif
    for (byte i = 0; i < 16; i++) {
      if (expected[i] != idRespRFID[i + 1]) {
        printf("\n[ACCESS DENIED]\n"); goto halt;
      }
      if (i == 15) {
        printf("\n[ACCESS GRANTED]\n"); goto halt;
      }
    }
  }

halt:
  wrReg(TxModeReg, 0x00);
  printf("\n-- cycle complete --\n");
}

int main() {
  setup();
  loop();
  return 0;
}