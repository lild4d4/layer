// ====================================================================
// Arduino code example for SPI Slave Mode
// Read unsigned short (two bytes) from SPI, send word to serial port
// On 16 MHz Arduino, can work at > 500 words per second
// J.Beale July 19 2011
// ====================================================================

#define SCK_PIN   13  // D13 = pin19 = PortB.5
#define MISO_PIN  12  // D12 = pin18 = PortB.4
#define MOSI_PIN  11  // D11 = pin17 = PortB.3
#define SS_PIN    10  // D10 = pin16 = PortB.2

#define UL unsigned long
#define US unsigned short

void SlaveInit(void) {
  // Set MISO output, all others input
  pinMode(SCK_PIN, INPUT);
  pinMode(MOSI_PIN, INPUT);
  pinMode(MISO_PIN, OUTPUT);  // (only if bidirectional mode needed)
  pinMode(SS_PIN, INPUT);

  /*  Setup SPI control register SPCR
  SPIE - Enables the SPI interrupt when 1
  SPE - Enables the SPI when 1
  DORD - Sends data least Significant Bit First when 1, most Significant Bit first when 0
  MSTR - Sets the Arduino in master mode when 1, slave mode when 0
  CPOL - Sets the data clock to be idle when high if set to 1, idle when low if set to 0
  CPHA - Samples data on the trailing edge of the data clock when 1, leading edge when 0
  SPR1 and SPR0 - Sets the SPI speed, 00 is fastest (4MHz) 11 is slowest (250KHz)   */
  
  // enable SPI subsystem and set correct SPI mode
  SPCR = (1<<SPE)|(0<<DORD)|(0<<MSTR)|(0<<CPOL)|(0<<CPHA)|(1<<SPR1)|(1<<SPR0); // SPI on

}

// SPI status register: SPSR
// SPI data register: SPDR

// ================================================================
// read in short as two bytes, with high-order byte coming in first
// ================================================================
byte ReadByte(void) {
  byte w;
  while(!(SPSR & (1<<SPIF))) ; // SPIF bit set when 8 bits received
  return (SPDR); // send back unsigned short value
}

void WriteByte(){
  while (!(SPSR & (1<<SPIF))){};
}

volatile unsigned long count = 0;

void measurePeriod() {
  count++;
}

void setup() {
  Serial.begin(115200);
  SlaveInit();  // set up SPI slave mode
  delay(10);
  Serial.println("SPI port reader v0.1");
  attachInterrupt(digitalPinToInterrupt(SCK_PIN), measurePeriod, RISING);
}

// ============================================================
// main loop: read in short word (2 bytes) from external SPI master
// and send value out via serial port
// On 16 MHz Arduino, works at > 500 words per secondf
// ============================================================
void loop() {
    byte buf[32];
    const byte w_len = 4;
    const byte r_len = 4;

    while(true) {
      while(digitalRead(SS_PIN)){}

      for (byte i = 0; i < w_len; i++)
        buf[i] = ReadByte();

      for (byte i = 0; i < r_len; i++) {
        SPDR = buf[i];
        WriteByte();
      }

      while(!digitalRead(SS_PIN)){}
      if (buf[0] == 0xDE && buf[1] == 0xAD && buf[2] == 0xBE && buf[3] == 0xEF) {
        Serial.println("  BEEF");
      } else {
        Serial.println("ERROR");
      }
    }

}  // end loop()
