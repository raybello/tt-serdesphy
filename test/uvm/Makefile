all: simulate

# Handle both Linux (nproc) and macOS (sysctl)
NPROC = 8 # $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)

VERILATOR := verilator
ifdef VERILATOR_ROOT
VERILATOR := $(VERILATOR_ROOT)/bin/verilator
endif
UVM_ROOT ?= lib/uvm-2017
UVM_ROOT_ABS = $(abspath $(UVM_ROOT))

SIM_DIR ?= serdesphy-sim
TOP_NAME := serdesphy
BIN_NAME := serdesphy
UVM_TEST ?= serdesphy_init_test
UVM_FILES := -I$(UVM_ROOT_ABS)/src $(UVM_ROOT_ABS)/src/uvm_pkg.sv
SERDESPHY_FILES := -f serdesphy.f
DEFINES := -DUVM_ENABLE_DEPRECATED_API -DUVM_NO_DPI
WARNINGS = -Wno-lint -Wno-TIMESCALEMOD -Wno-SYMRSVDWORD -Wno-CONSTRAINTIGN 
OTHER_FLAGS := --bbox-sys --timescale-override 1ns/1ps --assert --timing --trace
TEMPFILE := $(shell mktemp)

# Use --cc --exe --main instead of --binary for better macOS compatibility
$(SIM_DIR)/$(TOP_NAME).mk: $(shell find . -type f \( -name "*.sv" -o -name "*.svh" \))
	$(VERILATOR) --cc --exe --main $(UVM_FILES) $(SERDESPHY_FILES) $(DEFINES) $(WARNINGS) $(OTHER_FLAGS) \
		-Mdir $(SIM_DIR) --prefix $(TOP_NAME) -o $(BIN_NAME)

$(SIM_DIR)/$(BIN_NAME): $(SIM_DIR)/$(TOP_NAME).mk
	$(MAKE) -j $(NPROC) -C $(SIM_DIR) -f $(TOP_NAME).mk AR="/usr/bin/ar"

simulate: $(SIM_DIR)/$(BIN_NAME)
	./$(SIM_DIR)/$(BIN_NAME) +UVM_TESTNAME=$(UVM_TEST) | tee $(TEMPFILE)
	@grep "^UVM_ERROR\\s*:\\s*0$$" $(TEMPFILE) -q
	@grep "^UVM_FATAL\\s*:\\s*0$$" $(TEMPFILE) -q
	@grep "^Test PASSED$$" $(TEMPFILE) -q

rerun: clean simulate

clean:
	rm -rf $(SIM_DIR)

.PHONY: simulate clean rerun