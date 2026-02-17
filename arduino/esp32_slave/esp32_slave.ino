#include <Arduino.h>
extern "C" {
  #include "driver/spi_slave.h"
  #include "driver/gpio.h"
}

static constexpr spi_host_device_t SPIBUS = HSPI_HOST; // or VSPI_HOST

// Set pins to your wiring
static constexpr int PIN_SCK  = 18;
static constexpr int PIN_MOSI = 23;
static constexpr int PIN_MISO = 19;
static constexpr int PIN_SS   = 5;

// Set this to what your master clocks per CS-low burst (4 or 8 typically)
static constexpr int XFER_BYTES = 8;

static void spi_slave_init()
{
  spi_bus_config_t buscfg = {};
  buscfg.mosi_io_num = PIN_MOSI;
  buscfg.miso_io_num = PIN_MISO;
  buscfg.sclk_io_num = PIN_SCK;
  buscfg.quadwp_io_num = -1;
  buscfg.quadhd_io_num = -1;
  buscfg.max_transfer_sz = XFER_BYTES;

  spi_slave_interface_config_t slvcfg = {};
  slvcfg.spics_io_num = PIN_SS;
  slvcfg.queue_size = 2;
  slvcfg.mode = 0; // must match master (CPOL/CPHA)

  gpio_set_pull_mode((gpio_num_t)PIN_SS, GPIO_PULLUP_ONLY);

  esp_err_t err = spi_slave_initialize(SPIBUS, &buscfg, &slvcfg, SPI_DMA_CH_AUTO);
  if (err != ESP_OK) {
    Serial.printf("spi_slave_initialize failed: %d\n", (int)err);
    while (true) delay(1000);
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("ESP32 SPI slave: capture RX, always reply DE AD BE EF");
  spi_slave_init();
  
}

uint8_t print = 0;
void loop()
{
  uint8_t rx[XFER_BYTES];
  uint8_t tx[XFER_BYTES] = { 0x00, 0x00, 0x00, 0x00 , 0xDE, 0xAD, 0xBE, 0xEF};;

  memset(rx, 0, sizeof(rx));

  spi_slave_transaction_t t = {};
  t.length = 8 * XFER_BYTES;
  t.rx_buffer = rx;
  t.tx_buffer = tx;

  esp_err_t err = spi_slave_transmit(SPIBUS, &t, portMAX_DELAY);
  if (err != ESP_OK) {
    Serial.printf("spi_slave_transmit failed: %d\n", (int)err);
    return;
  }


  print++;
  if (print != 255) return;
  print = 0;
  // Print what we got (first 8 bytes max)
  // Serial.printf("RX:");
  // for (int i = 0; i < XFER_BYTES; i++) Serial.printf(" %02X", rx[i]);
  // Serial.println();


  // Check first 4 bytes like your Uno code
  if (XFER_BYTES >= 4 &&
      rx[0] == 0xDE && rx[1] == 0xAD && rx[2] == 0xBE && rx[3] == 0xEF) {
    Serial.println("  BEEF");
  } else {
    Serial.println("ERROR");
  }
}
