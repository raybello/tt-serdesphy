// Transaction driven into clk_reset_sequencer: one clock/reset
// directive. clk_period_ps/duty_cycle_pct/jitter_ps only matter for
// START_CLK; rst_assert_cycles only matters for DEASSERT_RST (it
// records how long reset was held, mostly for logging/coverage).

typedef enum {
  CLK_RESET_ASSERT_RST,
  CLK_RESET_DEASSERT_RST,
  CLK_RESET_START_CLK,
  CLK_RESET_STOP_CLK
} clk_reset_kind_e;

class clk_reset_tr extends uvm_sequence_item;

  rand clk_reset_kind_e kind;

  rand int unsigned clk_period_ps;
  rand int unsigned duty_cycle_pct;
  rand int unsigned jitter_ps;
  rand int unsigned rst_assert_cycles;

  `uvm_object_utils_begin(clk_reset_tr)
    `uvm_field_enum(clk_reset_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(clk_period_ps, UVM_ALL_ON)
    `uvm_field_int(duty_cycle_pct, UVM_ALL_ON)
    `uvm_field_int(jitter_ps, UVM_ALL_ON)
    `uvm_field_int(rst_assert_cycles, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "clk_reset_tr");
    super.new(name);
  endfunction

endclass : clk_reset_tr
