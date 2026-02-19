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
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports cs0]
# pin 1
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports cs1]
# pin 2
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports sclk]
# pin 3
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports mosi]
# pin 4
set_property -dict {PACKAGE_PIN R12 IOSTANDARD LVCMOS33} [get_ports miso]

#### Other pins
# pin 5 - led ext 0
# set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports rst_o]
# #IO_L14P_T2_SRCC_14 Sch=ck_io[5]
# pin 6 - led ext 1
#set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { ck_io6  }]; #IO_L14N_T2_SRCC_14 Sch=ck_io[6]
# pin 7 - led ext 2
#set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { ck_io7  }]; #IO_L15N_T2_DQS_DOUT_CSO_B_14 Sch=ck_io[7]
# pin 8  - trigger door open?
#set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { ck_io8  }]; #IO_L11P_T1_SRCC_14 Sch=ck_io[8]

## ChipKit Inner Digital Header
set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports {last_read[0]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {last_read[1]}]
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports {last_read[2]}]
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports {last_read[3]}]
set_property -dict {PACKAGE_PIN R11 IOSTANDARD LVCMOS33} [get_ports {last_read[4]}]
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports {last_read[5]}]
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports {last_read[6]}]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {last_read[7]}]
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
set_property PACKAGE_PIN H5 [get_ports {led[0]}]
set_property PACKAGE_PIN J5 [get_ports {led[1]}]
set_property PACKAGE_PIN T9 [get_ports {led[2]}]
set_property PACKAGE_PIN T10 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

# Clock constraints
create_clock -period 10.000 [get_ports clk]

# connect_debug_port u_ila_0/probe1 [get_nets [list {u_spi/p_1_in[0]} {u_spi/p_1_in[1]} {u_spi/p_1_in[2]} {u_spi/p_1_in[3]} {u_spi/p_1_in[4]} {u_spi/p_1_in[5]} {u_spi/p_1_in[6]} {u_spi/p_1_in[7]}]]

connect_debug_port u_ila_0/probe1 [get_nets [list {last_read_OBUF[0]} {last_read_OBUF[1]} {last_read_OBUF[2]} {last_read_OBUF[3]} {last_read_OBUF[4]} {last_read_OBUF[5]} {last_read_OBUF[6]} {last_read_OBUF[7]}]]
connect_debug_port u_ila_0/probe2 [get_nets [list cs1_OBUF]]
connect_debug_port u_ila_0/probe3 [get_nets [list cs0_OBUF]]
connect_debug_port u_ila_0/probe4 [get_nets [list miso_IBUF]]
connect_debug_port u_ila_0/probe5 [get_nets [list mosi_OBUF]]
connect_debug_port u_ila_0/probe7 [get_nets [list sclk_OBUF]]


connect_debug_port u_ila_0/probe5 [get_nets [list cs_0_OBUF]]
connect_debug_port u_ila_0/probe7 [get_nets [list cs_1_OBUF]]
connect_debug_port u_ila_0/probe14 [get_nets [list spi_miso_IBUF]]
connect_debug_port u_ila_0/probe16 [get_nets [list spi_mosi_OBUF]]
connect_debug_port u_ila_0/probe18 [get_nets [list spi_sclk_OBUF]]

connect_debug_port u_ila_0/probe7 [get_nets [list u_dut/get_key]]


connect_debug_port u_ila_0/probe0 [get_nets [list {u_dut/u_eeprom_ctrl/state[0]} {u_dut/u_eeprom_ctrl/state[1]} {u_dut/u_eeprom_ctrl/state[2]} {u_dut/u_eeprom_ctrl/state[3]} {u_dut/u_eeprom_ctrl/state[4]} {u_dut/u_eeprom_ctrl/state[5]}]]
connect_debug_port u_ila_0/probe1 [get_nets [list {u_dut/u_eeprom_ctrl/u_eeprom_spi/state[0]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/state[1]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/state[2]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/state[3]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/state[4]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/state[5]}]]
connect_debug_port u_ila_0/probe2 [get_nets [list {u_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[0]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[1]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[2]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[3]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[4]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[5]} {u_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[6]}]]
connect_debug_port u_ila_0/probe3 [get_nets [list {u_dut/spi_r_len[0]} {u_dut/spi_r_len[1]} {u_dut/spi_r_len[2]} {u_dut/spi_r_len[3]} {u_dut/spi_r_len[4]} {u_dut/spi_r_len[5]}]]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_dut/spi_w_len[0]} {u_dut/spi_w_len[1]} {u_dut/spi_w_len[2]} {u_dut/spi_w_len[3]} {u_dut/spi_w_len[4]} {u_dut/spi_w_len[5]}]]
connect_debug_port u_ila_0/probe7 [get_nets [list u_dut/busy]]
connect_debug_port u_ila_0/probe10 [get_nets [list u_dut/cs_0]]
connect_debug_port u_ila_0/probe11 [get_nets [list u_dut/cs_1]]
connect_debug_port u_ila_0/probe12 [get_nets [list u_dut/done]]
connect_debug_port u_ila_0/probe13 [get_nets [list u_dut/u_eeprom_ctrl/u_eeprom_spi/eeprom_busy]]
connect_debug_port u_ila_0/probe14 [get_nets [list u_dut/u_eeprom_ctrl/u_eeprom_spi/eeprom_done]]
connect_debug_port u_ila_0/probe17 [get_nets [list u_dut/n_0_0]]
connect_debug_port u_ila_0/probe20 [get_nets [list u_dut/spi_busy]]
connect_debug_port u_ila_0/probe21 [get_nets [list u_dut/u_eeprom_ctrl/u_eeprom_spi/spi_busy]]
connect_debug_port u_ila_0/probe22 [get_nets [list u_dut/u_eeprom_ctrl/u_eeprom_spi/spi_done]]
connect_debug_port u_ila_0/probe23 [get_nets [list u_dut/spi_done]]
connect_debug_port u_ila_0/probe24 [get_nets [list u_dut/spi_miso]]
connect_debug_port u_ila_0/probe25 [get_nets [list u_dut/spi_mosi]]
connect_debug_port u_ila_0/probe26 [get_nets [list u_dut/spi_sclk]]
connect_debug_port u_ila_0/probe27 [get_nets [list u_dut/spi_start]]
connect_debug_port u_ila_0/probe28 [get_nets [list u_dut/u_eeprom_ctrl/u_eeprom_spi/spi_start]]
connect_debug_port u_ila_0/probe29 [get_nets [list u_dut/start]]





connect_debug_port u_ila_0/probe10 [get_nets [list {state[0]} {state[1]} {state[2]}]]
connect_debug_port u_ila_0/probe22 [get_nets [list miso_IBUF]]
connect_debug_port u_ila_0/probe24 [get_nets [list rst_IBUF]]


connect_debug_port u_ila_0/probe23 [get_nets [list p_0_in]]
connect_debug_port u_ila_0/probe24 [get_nets [list rst_o_OBUF]]



connect_debug_port u_ila_0/probe9 [get_nets [list {spi_dut/u_mfrc_top/u_mfrc_core/state[0]} {spi_dut/u_mfrc_top/u_mfrc_core/state[1]} {spi_dut/u_mfrc_top/u_mfrc_core/state[2]} {spi_dut/u_mfrc_top/u_mfrc_core/state[3]} {spi_dut/u_mfrc_top/u_mfrc_core/state[4]}]]

create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 32768 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_IBUF_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 7 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {spi_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[0]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[1]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[2]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[3]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[4]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[5]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/lat_addr[6]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 6 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {spi_dut/u_mfrc_top/state[0]} {spi_dut/u_mfrc_top/state[1]} {spi_dut/u_mfrc_top/state[2]} {spi_dut/u_mfrc_top/state[3]} {spi_dut/u_mfrc_top/state[4]} {spi_dut/u_mfrc_top/state[5]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 6 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {spi_dut/u_eeprom_ctrl/state[0]} {spi_dut/u_eeprom_ctrl/state[1]} {spi_dut/u_eeprom_ctrl/state[2]} {spi_dut/u_eeprom_ctrl/state[3]} {spi_dut/u_eeprom_ctrl/state[4]} {spi_dut/u_eeprom_ctrl/state[5]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 3 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {mfrc_rx_last_bits[0]} {mfrc_rx_last_bits[1]} {mfrc_rx_last_bits[2]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 3 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {mfrc_tx_last_bits[0]} {mfrc_tx_last_bits[1]} {mfrc_tx_last_bits[2]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 5 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {mfrc_tx_len[0]} {mfrc_tx_len[1]} {mfrc_tx_len[2]} {mfrc_tx_len[3]} {mfrc_tx_len[4]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 16 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {mfrc_atqa[0]} {mfrc_atqa[1]} {mfrc_atqa[2]} {mfrc_atqa[3]} {mfrc_atqa[4]} {mfrc_atqa[5]} {mfrc_atqa[6]} {mfrc_atqa[7]} {mfrc_atqa[8]} {mfrc_atqa[9]} {mfrc_atqa[10]} {mfrc_atqa[11]} {mfrc_atqa[12]} {mfrc_atqa[13]} {mfrc_atqa[14]} {mfrc_atqa[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 4 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {led_OBUF[0]} {led_OBUF[1]} {led_OBUF[2]} {led_OBUF[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 5 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {mfrc_rx_len[0]} {mfrc_rx_len[1]} {mfrc_rx_len[2]} {mfrc_rx_len[3]} {mfrc_rx_len[4]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 3 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list {spi_dut/u_mfrc_top/u_mfrc_reg_if/state[0]} {spi_dut/u_mfrc_top/u_mfrc_reg_if/state[1]} {spi_dut/u_mfrc_top/u_mfrc_reg_if/state[2]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 6 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list {spi_dut/u_eeprom_ctrl/u_eeprom_spi/state[0]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/state[1]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/state[2]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/state[3]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/state[4]} {spi_dut/u_eeprom_ctrl/u_eeprom_spi/state[5]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list cs0_OBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list cs1_OBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 1 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list spi_dut/u_eeprom_ctrl/u_eeprom_spi/eeprom_busy]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 1 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list spi_dut/u_eeprom_ctrl/u_eeprom_spi/eeprom_done]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 1 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list mfrc_card_present]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe16]
set_property port_width 1 [get_debug_ports u_ila_0/probe16]
connect_debug_port u_ila_0/probe16 [get_nets [list mfrc_init_done]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe17]
set_property port_width 1 [get_debug_ports u_ila_0/probe17]
connect_debug_port u_ila_0/probe17 [get_nets [list mfrc_rx_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe18]
set_property port_width 1 [get_debug_ports u_ila_0/probe18]
connect_debug_port u_ila_0/probe18 [get_nets [list mfrc_tx_ready]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe19]
set_property port_width 1 [get_debug_ports u_ila_0/probe19]
connect_debug_port u_ila_0/probe19 [get_nets [list mfrc_tx_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe20]
set_property port_width 1 [get_debug_ports u_ila_0/probe20]
connect_debug_port u_ila_0/probe20 [get_nets [list miso_IBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe21]
set_property port_width 1 [get_debug_ports u_ila_0/probe21]
connect_debug_port u_ila_0/probe21 [get_nets [list mosi_OBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe22]
set_property port_width 1 [get_debug_ports u_ila_0/probe22]
connect_debug_port u_ila_0/probe22 [get_nets [list rst_IBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe23]
set_property port_width 1 [get_debug_ports u_ila_0/probe23]
connect_debug_port u_ila_0/probe23 [get_nets [list sclk_OBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe24]
set_property port_width 1 [get_debug_ports u_ila_0/probe24]
connect_debug_port u_ila_0/probe24 [get_nets [list spi_dut/u_eeprom_ctrl/u_eeprom_spi/spi_busy]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe25]
set_property port_width 1 [get_debug_ports u_ila_0/probe25]
connect_debug_port u_ila_0/probe25 [get_nets [list spi_dut/u_eeprom_ctrl/u_eeprom_spi/spi_done]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe26]
set_property port_width 1 [get_debug_ports u_ila_0/probe26]
connect_debug_port u_ila_0/probe26 [get_nets [list spi_dut/u_eeprom_ctrl/u_eeprom_spi/spi_start]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]
