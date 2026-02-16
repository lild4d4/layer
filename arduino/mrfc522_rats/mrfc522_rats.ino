/**
 * LAYR Guardian
 * Purpose: Read Card ID via ISO 14443-4 (RATS + SELECT + GET_ID)
 */

#include <Arduino.h>
#include <SPI.h>
#include <MFRC522v2.h>
#include <MFRC522DriverSPI.h>
#include <MFRC522DriverPinSimple.h>
#include <MFRC522Debug.h>

#define PIN_SS    10

MFRC522DriverPinSimple ss_pin(PIN_SS);
MFRC522DriverSPI driver{ss_pin};
MFRC522 mfrc522{driver};

uint8_t iBlockPCB = 0x02;

void toggleBlock() {
    iBlockPCB ^= 0x01;
}

bool sendRaw(byte *data, byte dataLen, byte *response, byte *responseLen) {
    MFRC522::StatusCode status = mfrc522.PCD_TransceiveData(
        data, dataLen,
        response, responseLen,
        nullptr, 0, false
    );

    Serial.print(F("  TX: "));
    for (byte i = 0; i < dataLen; i++) {
        if (data[i] < 0x10) Serial.print("0");
        Serial.print(data[i], HEX); Serial.print(" ");
    }
    Serial.println();

    Serial.print(F("  RX: "));
    for (byte i = 0; i < *responseLen; i++) {
        if (response[i] < 0x10) Serial.print("0");
        Serial.print(response[i], HEX); Serial.print(" ");
    }
    Serial.println();

    Serial.print(F("  Status: 0x"));
    Serial.println((byte)status, HEX);

    delay(5);
    return (status == MFRC522::StatusCode::STATUS_OK);
}

bool sendIBlock(byte *payload, byte payloadLen, byte *response, byte *responseLen) {
    byte frame[payloadLen + 1];
    frame[0] = iBlockPCB;
    memcpy(frame + 1, payload, payloadLen);

    // Clear FIFO before transmission to ensure clean state
    driver.PCD_WriteRegister(MFRC522::PCD_Register::FIFOLevelReg, 0x80);
    
    bool ok = sendRaw(frame, sizeof(frame), response, responseLen);
    if (ok) toggleBlock();
    return ok;
}

bool doRATS(byte *response, byte *responseLen) {
    byte rats[] = {0xE0, 0x50};

    driver.PCD_WriteRegister(MFRC522::PCD_Register::TxModeReg, 0x80);
    driver.PCD_WriteRegister(MFRC522::PCD_Register::RxModeReg, 0x00);

    MFRC522::StatusCode status = mfrc522.PCD_TransceiveData(
        rats, sizeof(rats),
        response, responseLen,
        nullptr, 0, false
    );

    if (status == MFRC522::StatusCode::STATUS_OK) {
        // Enable RX CRC for I-Block exchanges
        driver.PCD_WriteRegister(MFRC522::PCD_Register::RxModeReg, 0x80);
        // Clear any leftover bits from RATS exchange
        driver.PCD_WriteRegister(MFRC522::PCD_Register::BitFramingReg, 0x00);
        
        // ISO 14443-4 requires longer timeout - increase timer prescaler
        // Default: TPrescaler=0x0A9 (169) → 25μs period, 677ms timeout
        // New: TPrescaler=0xD3E (3390) → 500μs period, ~13.4s timeout
        driver.PCD_WriteRegister(MFRC522::PCD_Register::TModeReg, 0x8D);      // TAuto=1, TPrescaler[11:8]=0xD
        driver.PCD_WriteRegister(MFRC522::PCD_Register::TPrescalerReg, 0x3E); // TPrescaler[7:0]=0x3E
        
        Serial.print(F("  [OK] RATS ATS: "));
        for (byte i = 0; i < *responseLen; i++) {
            if (response[i] < 0x10) Serial.print("0");
            Serial.print(response[i], HEX); Serial.print(" ");
        }
        Serial.println();
        return true;
    } else {
        Serial.print(F("  [!] RATS Failed: 0x"));
        Serial.println((byte)status, HEX);
        return false;
    }
}

void setup() {
    Serial.begin(115200);
    
    delay(3000); 

    Serial.println(F("\n\n=================================="));
    Serial.println(F("   LAYR GUARDIAN - DEBUG MODE"));
    Serial.println(F("=================================="));

    SPI.begin();
    Serial.println(F("[1] SPI Bus Started"));

    mfrc522.PCD_Init();
    Serial.println(F("[2] MFRC522 Initialized"));

    Serial.print(F("[3] Reader Firmware Version: 0x"));
    byte v = driver.PCD_ReadRegister(MFRC522::PCD_Register::VersionReg);
    Serial.println(v, HEX);

    if (v == 0x00 || v == 0xFF) {
        Serial.println(F("!!! CRITICAL FAILURE !!!"));
        Serial.println(F("Reader not found. Check wiring: MISO, MOSI, SCK, SS."));
        while(1);
    } else {
        Serial.println(F("[OK] Reader hardware is alive."));
        
        mfrc522.PCD_SetAntennaGain(0x07 << 4);
        Serial.println(F("[4] Antenna Gain set to Max (48dB)"));
    }

    Serial.println(F("Ready — present card..."));
}

void loop() {
    iBlockPCB = 0x02;

    if (!mfrc522.PICC_IsNewCardPresent()) return;
    if (!mfrc522.PICC_ReadCardSerial()) return;

    Serial.print(F("\n[!] Card Detected! UID: "));
    for (byte i = 0; i < mfrc522.uid.size; i++) {
        if (mfrc522.uid.uidByte[i] < 0x10) Serial.print("0");
        Serial.print(mfrc522.uid.uidByte[i], HEX); Serial.print(" ");
    }
    Serial.println();

    // Enable hardware CRC generation for ISO 14443-4 (RATS + APDUs)
    // Library's PCD_Init sets TxCRCEn=0, but raw TransceiveData needs it
    driver.PCD_WriteRegister(MFRC522::PCD_Register::TxModeReg, 0x80);

    Serial.println(F("[RATS]"));
    byte atsBuffer[32];
    byte atsLen = sizeof(atsBuffer);
    if (!doRATS(atsBuffer, &atsLen)) {
        Serial.println(F("RATS failed"));
        goto halt;
    }
    
    // Give card time to process RATS and enter protocol state
    delay(10);

    {
        Serial.println(F("[SELECT F000000CDC00]"));
        byte selectCmd[] = {
            0x00, 0xA4, 0x04, 0x00, 0x06,
            0xF0, 0x00, 0x00, 0x0C, 0xDC, 0x00
        };
        byte selectResp[32];
        byte selectLen = sizeof(selectResp);

        if (!sendIBlock(selectCmd, sizeof(selectCmd), selectResp, &selectLen)) {
            Serial.println(F("SELECT failed"));
            goto halt;
        }

        // Hardware CRC strips CRC bytes: response is PCB + data + SW1 + SW2
        // SW1/SW2 are at the end: [len-2]=SW1, [len-1]=SW2
        if (selectResp[selectLen - 2] != 0x90 || selectResp[selectLen - 1] != 0x00) {
            Serial.println(F("SELECT returned error SW"));
            goto halt;
        }

        Serial.println(F("[GET_ID]"));
        byte getIdCmd[] = {0x80, 0x12, 0x00, 0x00, 0x00};
        byte idResp[32];
        byte idLen = sizeof(idResp);

        if (!sendIBlock(getIdCmd, sizeof(getIdCmd), idResp, &idLen)) {
            Serial.println(F("GET_ID failed"));
            goto halt;
        }

        // Response: PCB(1) + ID(N) + SW(2) - hardware strips CRC
        byte idDataLen = idLen - 3;
        Serial.print(F("Card ID: "));
        for (byte i = 1; i <= idDataLen; i++) {
            if (idResp[i] < 0x10) Serial.print("0");
            Serial.print(idResp[i], HEX); Serial.print(" ");
        }
        Serial.println();
    }

halt:
    // Disable hardware CRC — PICC_HaltA calculates CRC manually
    driver.PCD_WriteRegister(MFRC522::PCD_Register::TxModeReg, 0x00);
    mfrc522.PICC_HaltA();
    mfrc522.PCD_StopCrypto1();
    delay(2000);
}