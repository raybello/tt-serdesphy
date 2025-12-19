# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog

SRC_DIR = $(PWD)/../src

# DIG_DIR = $(SRC_DIR)/digital
# ANA_DIR = $(SRC_DIR)/analog

# TX_DIR = $(DIG_DIR)/tx
# RX_DIR = $(DIG_DIR)/rx
# PLL_DIR = $(DIG_DIR)/pll
# CSR_DIR = $(DIG_DIR)/csr
# POR_DIR = $(DIG_DIR)/por
# COM_DIR = $(DIG_DIR)/common

# ANA_COMMON_DIR = $(ANA_DIR)/ana_common
# ANA_PLL_DIR = $(ANA_DIR)/ana_pll
# ANA_RX_DIR = $(ANA_DIR)/ana_rx
# ANA_TX_DIR = $(ANA_DIR)/ana_tx

PROJECT_SOURCES := $(notdir $(shell find $(SRC_DIR) -name '*.v'))

# TX_SOURCES	:= $(notdir $(shell find $(TX_DIR) -name '*.v'))
# RX_SOURCES	:= $(notdir $(shell find $(RX_DIR) -name '*.v'))
# PLL_SOURCES	:= $(notdir $(shell find $(PLL_DIR) -name '*.v'))
# CSR_SOURCES	:= $(notdir $(shell find $(CSR_DIR) -name '*.v'))
# POR_SOURCES	:= $(notdir $(shell find $(POR_DIR) -name '*.v'))
# COM_SOURCES	:= $(notdir $(shell find $(COM_DIR) -name '*.v'))

# ANA_COMMON_SOURCES := $(notdir $(shell find $(ANA_COMMON_DIR) -name '*.v'))
# ANA_PLL_SOURCES := $(notdir $(shell find $(ANA_PLL_DIR) -name '*.v'))
# ANA_RX_SOURCES := $(notdir $(shell find $(ANA_RX_DIR) -name '*.v'))
# ANA_TX_SOURCES := $(notdir $(shell find $(ANA_TX_DIR) -name '*.v'))

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
# VERILOG_SOURCES += $(addprefix $(TX_DIR)/,$(TX_SOURCES))
# VERILOG_SOURCES += $(addprefix $(RX_DIR)/,$(RX_SOURCES))
# VERILOG_SOURCES += $(addprefix $(PLL_DIR)/,$(PLL_SOURCES))
# VERILOG_SOURCES += $(addprefix $(CSR_DIR)/,$(CSR_SOURCES))
# VERILOG_SOURCES += $(addprefix $(POR_DIR)/,$(POR_SOURCES))
# VERILOG_SOURCES += $(addprefix $(COM_DIR)/,$(COM_SOURCES))

# VERILOG_SOURCES += $(addprefix $(ANA_COMMON_DIR)/,$(ANA_COMMON_SOURCES))
# VERILOG_SOURCES += $(addprefix $(ANA_PLL_DIR)/,$(ANA_PLL_SOURCES))
# VERILOG_SOURCES += $(addprefix $(ANA_RX_DIR)/,$(ANA_RX_SOURCES))
# VERILOG_SOURCES += $(addprefix $(ANA_TX_DIR)/,$(ANA_TX_SOURCES))

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DSIM
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
