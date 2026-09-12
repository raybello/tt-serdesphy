// Filelist for the serdesphy UVM testbench (absolute paths).

+incdir+/Users/raybello/Github/verilator-verification/third-party/sv-tests/third_party/tests/uvm/src
+incdir+/Users/raybello/Github/tt-serdesphy/src/digital/csr
+incdir+/Users/raybello/Github/tt-serdesphy/uvm_tb
+incdir+/Users/raybello/Github/tt-serdesphy/uvm_tb/ral

-DUVM_NO_DPI

// UVM library (from the verilator-verification sv-tests checkout)
/Users/raybello/Github/verilator-verification/third-party/sv-tests/third_party/tests/uvm/src/uvm_pkg.sv

// DUT sources
/Users/raybello/Github/tt-serdesphy/src/digital/common/serdesphy_debug_mux.v
/Users/raybello/Github/tt-serdesphy/src/digital/common/serdesphy_reset_synchronizer.v
/Users/raybello/Github/tt-serdesphy/src/digital/csr/serdesphy_csr_top.v
/Users/raybello/Github/tt-serdesphy/src/digital/csr/serdesphy_i2c_slave.v
/Users/raybello/Github/tt-serdesphy/src/digital/csr/serdesphy_registerInterface.v
/Users/raybello/Github/tt-serdesphy/src/digital/csr/serdesphy_serialInterface.v
/Users/raybello/Github/tt-serdesphy/src/digital/pll/serdesphy_clock_manager.v
/Users/raybello/Github/tt-serdesphy/src/digital/pll/serdesphy_pll_ctrl.v
/Users/raybello/Github/tt-serdesphy/src/digital/por/serdesphy_por.v
/Users/raybello/Github/tt-serdesphy/src/digital/rx/serdesphy_deserializer_if.v
/Users/raybello/Github/tt-serdesphy/src/digital/rx/serdesphy_manchester_decoder.v
/Users/raybello/Github/tt-serdesphy/src/digital/rx/serdesphy_prbs_checker.v
/Users/raybello/Github/tt-serdesphy/src/digital/rx/serdesphy_rx_fifo.v
/Users/raybello/Github/tt-serdesphy/src/digital/rx/serdesphy_rx_top.v
/Users/raybello/Github/tt-serdesphy/src/digital/rx/serdesphy_word_disassembler.v
/Users/raybello/Github/tt-serdesphy/src/digital/tx/serdesphy_manchester_encoder.v
/Users/raybello/Github/tt-serdesphy/src/digital/tx/serdesphy_prbs_generator.v
/Users/raybello/Github/tt-serdesphy/src/digital/tx/serdesphy_serializer_if.v
/Users/raybello/Github/tt-serdesphy/src/digital/tx/serdesphy_tx_data_mux.v
/Users/raybello/Github/tt-serdesphy/src/digital/tx/serdesphy_tx_fifo.v
/Users/raybello/Github/tt-serdesphy/src/digital/tx/serdesphy_tx_top.v
/Users/raybello/Github/tt-serdesphy/src/digital/tx/serdesphy_word_assembler.v
/Users/raybello/Github/tt-serdesphy/src/digital/serdesphy_pcs.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_common/serdesphy_ana_analog_debug_buffer.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_common/serdesphy_ana_bias_generator.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_common/serdesphy_ana_clk_enable.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_pll/serdesphy_ana_frequency_divider.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_pll/serdesphy_ana_loopback_switch.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_pll/serdesphy_ana_phase_frequency_detector.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_pll/serdesphy_ana_pll_charge_pump.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_pll/serdesphy_ana_pll_loop_filter.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_pll/serdesphy_ana_pll_vco.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_pll/serdesphy_ana_pll.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_rx/serdesphy_ana_cdr_vco.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_rx/serdesphy_ana_cdr.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_rx/serdesphy_ana_deserializer.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_rx/serdesphy_ana_rx_differential_receiver.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_tx/serdesphy_ana_serializer.v
/Users/raybello/Github/tt-serdesphy/src/analog/ana_tx/serdesphy_ana_tx_differential_driver.v
/Users/raybello/Github/tt-serdesphy/src/analog/serdesphy_pma.v
/Users/raybello/Github/tt-serdesphy/src/serdesphy_top.v
/Users/raybello/Github/tt-serdesphy/src/project.v

// Test harness: defines, system_pkg, system_if, checkers, binds, system.sv
-f /Users/raybello/Github/tt-serdesphy/uvm_tb/test_harness/filelist.f

// RAL (bus-agnostic register model)
/Users/raybello/Github/tt-serdesphy/uvm_tb/ral/ral_pkg.sv

// UVM environment (agents, env, vseq_lib, tests) + top-level module
/Users/raybello/Github/tt-serdesphy/uvm_tb/serdesphy_pkg.sv
/Users/raybello/Github/tt-serdesphy/uvm_tb/tb_top.sv
