# https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-100-Master.xdc

# Clock pin
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# SPI
#set_property -dict { PACKAGE_PIN G1    IOSTANDARD LVCMOS33 } [get_ports { miso }]; #IO_L17N_T2_35 Sch=ck_miso
#set_property -dict { PACKAGE_PIN H1    IOSTANDARD LVCMOS33 } [get_ports { mosi }]; #IO_L17P_T2_35 Sch=ck_mosi
#set_property -dict { PACKAGE_PIN F1    IOSTANDARD LVCMOS33 } [get_ports { sclk }]; #IO_L18P_T2_35 Sch=ck_sck
#set_property -dict { PACKAGE_PIN C1    IOSTANDARD LVCMOS33 } [get_ports { ss }]; #IO_L16N_T2_35 Sch=ck_ss

### SPI
# pin 0 -ok
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports cs_0]
# pin 1
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports cs_1]
# pin 2
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports spi_sclk]
# pin 3
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports spi_mosi]
# pin 4
set_property -dict {PACKAGE_PIN R12 IOSTANDARD LVCMOS33} [get_ports spi_miso]

#### Other pins
# pin 5 - led ext 0
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports status_fault]
# #IO_L14P_T2_SRCC_14 Sch=ck_io[5]
# pin 6 - led ext 1
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports status_unlock]
# pin 7 - led ext 2
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports status_busy]
# pin 8  - trigger door open?
#set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { ck_io8  }]; #IO_L11P_T1_SRCC_14 Sch=ck_io[8]

## ChipKit Inner Digital Header
# set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports {last_read[0]}]
# set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {last_read[1]}]
# set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports {last_read[2]}]
# set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports {last_read[3]}]
# set_property -dict {PACKAGE_PIN R11 IOSTANDARD LVCMOS33} [get_ports {last_read[4]}]
# set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports {last_read[5]}]
# set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports {last_read[6]}]
# set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {last_read[7]}]
#set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { ck_io35 }]; #IO_L11N_T1_SRCC_14 Sch=ck_io[35]
#set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { ck_io36 }]; #IO_L8P_T1_D11_14 Sch=ck_io[36]
#set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { ck_io37 }]; #IO_L17P_T2_A14_D30_14 Sch=ck_io[37]
#set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { ck_io38 }]; #IO_L7N_T1_D10_14 Sch=ck_io[38]
#set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { ck_io39 }]; #IO_L7P_T1_D09_14 Sch=ck_io[39]
#set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { ck_io40 }]; #IO_L9N_T1_DQS_D13_14 Sch=ck_io[40]
#set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { ck_io41 }]; #IO_L9P_T1_DQS_14 Sch=ck_io[41]

## Switches
set_property -dict {PACKAGE_PIN A8 IOSTANDARD LVCMOS33} [get_ports rst]
#set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]; #IO_L13P_T2_MRCC_16 Sch=sw[1]
#set_property -dict { PACKAGE_PIN C10   IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]; #IO_L13N_T2_MRCC_16 Sch=sw[2]
#set_property -dict { PACKAGE_PIN A10   IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]; #IO_L14P_T2_SRCC_16 Sch=sw[3]

# leds
# set_property PACKAGE_PIN H5 [get_ports {led[0]}]
# set_property PACKAGE_PIN J5 [get_ports {led[1]}]
# set_property PACKAGE_PIN T9 [get_ports {led[2]}]
# set_property PACKAGE_PIN T10 [get_ports {led[3]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

# Clock constraints
create_clock -period 10.000 [get_ports clk]
