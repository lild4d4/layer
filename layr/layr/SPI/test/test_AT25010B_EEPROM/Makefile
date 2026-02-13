##############################################################################
# Makefile for cocotb + Icarus Verilog (or Verilator)
# Usage:
#   make                  – run all tests
#   make SIM=verilator    – run with Verilator instead
#   make TESTCASE=test_read_basic  – run a single test
##############################################################################

TOPLEVEL_LANG  = verilog
SIM           ?= icarus       # icarus | verilator | xcelium | vcs

# All three RTL files + the wrapper
VERILOG_SOURCES = \
    $(PWD)/../../src/axi_spi_master.sv \
    $(PWD)/../../src/axi_lite_master.sv \
    $(PWD)/../../src/eeprom_spi.sv \
    $(PWD)/eeprom_wire_modules.sv

TOPLEVEL       = tb_top
MODULE         = test_eeprom   # Python test file (test_eeprom.py)

# Icarus: allow SystemVerilog constructs used by axi_spi_master
COMPILE_ARGS  += -g2012

# Verilator (uncomment if SIM=verilator)
# EXTRA_ARGS += --trace

include $(shell cocotb-config --makefiles)/Makefile.sim

