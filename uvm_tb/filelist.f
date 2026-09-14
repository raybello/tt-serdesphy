// Filelist for the serdesphy UVM testbench.
//
// Uses @@REPO_ROOT@@ / @@UVM_SRC_DIR@@ placeholder tokens instead of
// hardcoded absolute paths so the same file works on any machine (or CI
// runner). build.py resolves these into a real filelist under the build
// directory before invoking Verilator - see resolve_filelist() there.

+incdir+@@UVM_SRC_DIR@@
+incdir+@@REPO_ROOT@@/src/digital/csr
+incdir+@@REPO_ROOT@@/uvm_tb
+incdir+@@REPO_ROOT@@/uvm_tb/ral

-DUVM_NO_DPI

// UVM library
@@UVM_SRC_DIR@@/uvm_pkg.sv

// DUT sources
@@REPO_ROOT@@/src/digital/common/serdesphy_debug_mux.v
@@REPO_ROOT@@/src/digital/common/serdesphy_reset_synchronizer.v
@@REPO_ROOT@@/src/digital/csr/serdesphy_csr_top.v
@@REPO_ROOT@@/src/digital/csr/serdesphy_i2c_slave.v
@@REPO_ROOT@@/src/digital/csr/serdesphy_registerInterface.v
@@REPO_ROOT@@/src/digital/csr/serdesphy_serialInterface.v
@@REPO_ROOT@@/src/digital/pll/serdesphy_pll_ctrl.v
@@REPO_ROOT@@/src/digital/por/serdesphy_por.v
@@REPO_ROOT@@/src/digital/rx/serdesphy_deserializer_if.v
@@REPO_ROOT@@/src/digital/rx/serdesphy_manchester_decoder.v
@@REPO_ROOT@@/src/digital/rx/serdesphy_prbs_checker.v
@@REPO_ROOT@@/src/digital/rx/serdesphy_rx_fifo.v
@@REPO_ROOT@@/src/digital/rx/serdesphy_rx_top.v
@@REPO_ROOT@@/src/digital/rx/serdesphy_word_disassembler.v
@@REPO_ROOT@@/src/digital/tx/serdesphy_manchester_encoder.v
@@REPO_ROOT@@/src/digital/tx/serdesphy_prbs_generator.v
@@REPO_ROOT@@/src/digital/tx/serdesphy_serializer_if.v
@@REPO_ROOT@@/src/digital/tx/serdesphy_tx_data_mux.v
@@REPO_ROOT@@/src/digital/tx/serdesphy_tx_fifo.v
@@REPO_ROOT@@/src/digital/tx/serdesphy_tx_top.v
@@REPO_ROOT@@/src/digital/tx/serdesphy_word_assembler.v
@@REPO_ROOT@@/src/digital/serdesphy_pcs.v
@@REPO_ROOT@@/src/analog/ana_common/serdesphy_ana_analog_debug_buffer.v
@@REPO_ROOT@@/src/analog/ana_common/serdesphy_ana_bias_generator.v
@@REPO_ROOT@@/src/analog/ana_common/serdesphy_ana_clk_enable.v
@@REPO_ROOT@@/src/analog/ana_pll/serdesphy_ana_frequency_divider.v
@@REPO_ROOT@@/src/analog/ana_pll/serdesphy_ana_loopback_switch.v
@@REPO_ROOT@@/src/analog/ana_pll/serdesphy_ana_phase_frequency_detector.v
@@REPO_ROOT@@/src/analog/ana_pll/serdesphy_ana_pll_charge_pump.v
@@REPO_ROOT@@/src/analog/ana_pll/serdesphy_ana_pll_loop_filter.v
@@REPO_ROOT@@/src/analog/ana_pll/serdesphy_ana_pll_vco.v
@@REPO_ROOT@@/src/analog/ana_pll/serdesphy_ana_pll.v
@@REPO_ROOT@@/src/analog/ana_rx/serdesphy_ana_cdr_vco.v
@@REPO_ROOT@@/src/analog/ana_rx/serdesphy_ana_cdr.v
@@REPO_ROOT@@/src/analog/ana_rx/serdesphy_ana_deserializer.v
@@REPO_ROOT@@/src/analog/ana_rx/serdesphy_ana_rx_differential_receiver.v
@@REPO_ROOT@@/src/analog/ana_tx/serdesphy_ana_serializer.v
@@REPO_ROOT@@/src/analog/ana_tx/serdesphy_ana_tx_differential_driver.v
@@REPO_ROOT@@/src/analog/serdesphy_pma.v
@@REPO_ROOT@@/src/serdesphy_top.v
@@REPO_ROOT@@/src/project.v

// Test harness: defines, system_pkg, system_if, checkers, binds, system.sv
-f @@REPO_ROOT@@/uvm_tb/test_harness/filelist.f

// RAL (bus-agnostic register model)
@@REPO_ROOT@@/uvm_tb/ral/ral_pkg.sv

// UVM environment (agents, env, vseq_lib, tests) + top-level module
@@REPO_ROOT@@/uvm_tb/serdesphy_pkg.sv
@@REPO_ROOT@@/uvm_tb/tb_top.sv
