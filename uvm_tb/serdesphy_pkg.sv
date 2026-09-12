// Top UVM package for the serdesphy testbench: pulls in every
// agent/env/RAL/vseq/test class, `include`d (rather than separately
// compiled) in dependency order since they're plain classes with no
// package of their own.
//
// Depends on system_pkg (CSR address map) and system_if
// (test_harness/), both of which must already be compiled/imported
// by the time this file is read - see filelist.f.

package serdesphy_pkg;

  import uvm_pkg::*;
`include "uvm_macros.svh"

  import system_pkg::*;
  import ral_pkg::*;

  // ------------------------------------------------------------------
  // Configs
  // ------------------------------------------------------------------
  `include "env/configs/config_base.sv"
  `include "env/configs/clk_reset/clk_reset_base_cfg.sv"
  `include "env/configs/clk_reset/clk_reset_full_cfg.sv"

  // ------------------------------------------------------------------
  // clk_reset_agent
  // ------------------------------------------------------------------
  `include "agents/clk_reset_agent/clk_reset_tr.sv"
  `include "agents/clk_reset_agent/clk_reset_sequencer.sv"
  `include "agents/clk_reset_agent/clk_reset_driver.sv"
  `include "agents/clk_reset_agent/clk_reset_monitor.sv"
  `include "agents/clk_reset_agent/seq_lib/clk_reset_assert_rst_seq.sv"
  `include "agents/clk_reset_agent/seq_lib/clk_reset_deassert_rst_seq.sv"
  `include "agents/clk_reset_agent/seq_lib/clk_reset_start_clk_seq.sv"
  `include "agents/clk_reset_agent/seq_lib/clk_reset_stop_clk_seq.sv"
  `include "agents/clk_reset_agent/clk_reset_agent.sv"

  // ------------------------------------------------------------------
  // i2c_agent
  // ------------------------------------------------------------------
  `include "agents/i2c_agent/i2c_tr.sv"
  `include "agents/i2c_agent/i2c_sequencer.sv"
  `include "agents/i2c_agent/i2c_driver.sv"
  `include "agents/i2c_agent/i2c_monitor.sv"
  `include "agents/i2c_agent/seq_lib/i2c_write_reg_seq.sv"
  `include "agents/i2c_agent/seq_lib/i2c_read_reg_seq.sv"
  `include "agents/i2c_agent/i2c_agent.sv"

  // ------------------------------------------------------------------
  // RAL <-> i2c_agent glue (ral_pkg itself is bus-agnostic)
  // ------------------------------------------------------------------
  `include "ral/csr2i2c_adapter.sv"

  // ------------------------------------------------------------------
  // Coverage
  // ------------------------------------------------------------------
  `include "env/coverage/covergroups/clk_reset_cg.sv"
  `include "env/coverage/coverage.sv"

  // ------------------------------------------------------------------
  // Environment
  // ------------------------------------------------------------------
  `include "env/env.sv"

  // ------------------------------------------------------------------
  // Virtual sequence library
  // ------------------------------------------------------------------
  `include "vseq_lib/base_vseq.sv"
  `include "vseq_lib/reset/cold_reset_vseq.sv"
  `include "vseq_lib/init/csr_init_vseq.sv"
  `include "vseq_lib/init/system_init_vseq.sv"
  `include "vseq_lib/test_vseq/basic_test_vseq.sv"

  // ------------------------------------------------------------------
  // Tests
  // ------------------------------------------------------------------
  `include "tests/basic_test.sv"
  `include "tests/reset_test.sv"
  `include "tests/clk_test.sv"
  `include "tests/csr_rdwr_test.sv"

endpackage : serdesphy_pkg
