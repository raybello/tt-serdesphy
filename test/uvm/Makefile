all: simulate

NPROC = 8

# -------------------------------------
# Testbench setup
# -------------------------------------
VERILATOR := verilator
VERILATOR_ROOT =lib/verilator

ifdef VERILATOR_ROOT
VERILATOR := $(VERILATOR_ROOT)/bin/verilator
endif

UVM_ROOT ?=lib/uvm-2017
UVM_TEST ?= serdesphy_base_test

# 						

VERILOG_DEFINE_FILES = 	${UVM_ROOT}/src/uvm.sv \
						agents/sys/sys_pkg.sv \
						env/serdesphy_env_pkg.sv \
						seq/serdesphy_seq_pkg.sv \
						tests/serdesphy_test_pkg.sv \
						top/serdesphy_pkg.sv \
						top/serdesphy_system.sv \
						hdl/design.sv
VERILOG_INCLUDE_DIRS = top hdl env agents/sys seq tests ${UVM_ROOT}/src

# -------------------------------------
# Compilation/simulation configuration
# -------------------------------------
SIM_NAME ?= serdesphy
SIM_DIR ?= $(SIM_NAME)-sim
TEMPFILE := $(UVM_TEST).log
COMPILE_ARGS += --output-groups 8 -DUVM_NO_DPI
COMPILE_ARGS += --prefix $(SIM_NAME) -o $(SIM_NAME)
COMPILE_ARGS += $(addprefix +incdir+, $(VERILOG_INCLUDE_DIRS))
EXTRA_ARGS += --timescale 1ns/1ps --error-limit 100
WARNING_ARGS += -Wno-lint \
	-Wno-style \
	-Wno-SYMRSVDWORD \
	-Wno-IGNOREDRETURN \
	-Wno-ZERODLY

# -------------------------------------
# Make UVM test with Verilator
# -------------------------------------
$(SIM_DIR)/$(SIM_NAME).mk: $(wildcard hdl/*.sv)
	$(VERILATOR) --cc --exe --main --timing --trace -Mdir $(SIM_DIR) \
	${COMPILE_ARGS} ${EXTRA_ARGS} \
	${VERILOG_DEFINE_FILES} \
	${WARNING_ARGS}

$(SIM_DIR)/$(SIM_NAME): $(SIM_DIR)/$(SIM_NAME).mk
	$(MAKE) -j8 -C $(SIM_DIR) $(BUILD_ARGS) -f $(SIM_NAME).mk AR=/usr/bin/ar

rerun: clean simulate
	echo "Completed Rerun"
	

simulate: $(SIM_DIR)/$(SIM_NAME).mk $(SIM_DIR)/$(SIM_NAME)
	$(SIM_DIR)/$(SIM_NAME) +UVM_TESTNAME=$(UVM_TEST) | tee $(TEMPFILE)
	@grep "^UVM_ERROR\\s*:\\s*0$$" $(TEMPFILE) -q
	@grep "^UVM_FATAL\\s*:\\s*0$$" $(TEMPFILE) -q

clean:
	rm -rf simv*.daidir csrc
	rm -rf csrc* simv*
	rm -rf $(SIM_DIR)


.PHONY: simulate clean