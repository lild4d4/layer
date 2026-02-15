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
  SPCR = (1<<SPE)|(0<<DORD)|(0<<MSTR)|(0<<CPOL)|(0<<CPHA)|(0<<SPR1)|(0<<SPR0); 
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

void WriteByte(byte b){
  SPDR = b;
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
  SPCR = (1<<SPE)|(0<<DORD)|(0<<MSTR)|(0<<CPOL)|(0<<CPHA)|(0<<SPR1)|(1<<SPR0); // SPI on
}

// ============================================================
// main loop: read in short word (2 bytes) from external SPI master
// and send value out via serial port
// On 16 MHz Arduino, works at > 500 words per secondf
// ============================================================
void loop() {
  byte b;
  byte flag1;


     // SS_PIN = Digital_10 = ATmega328 Pin 16 =  PORTB.2
    // Note: digitalRead() takes 4.1 microseconds
    // NOTE: SS_PIN cannot be properly read this way while SPI module is active!

    while(digitalRead(SS_PIN)){}
    b = ReadByte();          // read unsigned short value

    
    while(!digitalRead(SS_PIN)){}
    while(digitalRead(SS_PIN)){}
    WriteByte(b);

    Serial.println(b);

}  // end loop()
