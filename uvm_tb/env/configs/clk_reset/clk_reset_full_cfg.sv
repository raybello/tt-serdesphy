// Stress configuration for clk_reset_agent: overrides the base
// constraints with a higher/wider frequency range, added jitter, and
// a longer reset pulse - used by clk_test / reset_test to exercise
// clk_checker and reset_checker beyond the nominal operating point.
//
// Constraint blocks with the same name as a base-class block replace
// it (standard SystemVerilog constraint overriding), so c_period /
// c_duty / c_jitter / c_rst_assert below fully supersede
// clk_reset_base_cfg's versions.

class clk_reset_full_cfg extends clk_reset_base_cfg;

  constraint c_period {
    clk_period_ps inside {[8_000 : 20_000]};  // faster than nominal
  }

  constraint c_duty {
    duty_cycle_pct inside {[35 : 65]};
  }

  constraint c_jitter {
    jitter_ps inside {[100 : 500]};
  }

  constraint c_rst_assert {
    rst_assert_cycles inside {[20 : 40]};
  }

  `uvm_object_utils(clk_reset_full_cfg)

  function new(string name = "clk_reset_full_cfg");
    super.new(name);
  endfunction

endclass : clk_reset_full_cfg
