# https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-100-Master.xdc

# Clock pin
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# SPI
#set_property -dict { PACKAGE_PIN G1    IOSTANDARD LVCMOS33 } [get_ports { miso }]; #IO_L17N_T2_35 Sch=ck_miso
#set_property -dict { PACKAGE_PIN H1    IOSTANDARD LVCMOS33 } [get_ports { mosi }]; #IO_L17P_T2_35 Sch=ck_mosi
#set_property -dict { PACKAGE_PIN F1    IOSTANDARD LVCMOS33 } [get_ports { sclk }]; #IO_L18P_T2_35 Sch=ck_sck
#set_property -dict { PACKAGE_PIN C1    IOSTANDARD LVCMOS33 } [get_ports { ss }]; #IO_L16N_T2_35 Sch=ck_ss

set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports miso]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports mosi]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports sclk]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports cs0]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports cs1]


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


connect_debug_port u_ila_0/probe1 [get_nets [list miso]]
connect_debug_port u_ila_0/probe5 [get_nets [list cs0_OBUF]]

connect_debug_port u_ila_0/probe1 [get_nets [list {u_spi/p_1_in[0]} {u_spi/p_1_in[1]} {u_spi/p_1_in[2]} {u_spi/p_1_in[3]} {u_spi/p_1_in[4]} {u_spi/p_1_in[5]} {u_spi/p_1_in[6]} {u_spi/p_1_in[7]}]]





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
set_property port_width 4 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {led_OBUF[0]} {led_OBUF[1]} {led_OBUF[2]} {led_OBUF[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 8 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {last_read_OBUF[0]} {last_read_OBUF[1]} {last_read_OBUF[2]} {last_read_OBUF[3]} {last_read_OBUF[4]} {last_read_OBUF[5]} {last_read_OBUF[6]} {last_read_OBUF[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list mosi_OBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list rst_IBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list sclk_OBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list cs0_OBUF]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]
