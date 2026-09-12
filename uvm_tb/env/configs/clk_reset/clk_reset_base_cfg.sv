// Base configuration for clk_reset_agent: nominal 24 MHz, 50% duty,
// no jitter, a "textbook" reset pulse width. clk_reset_full_cfg
// extends this with tighter/looser constraints to stress the clock
// generator and its checker.

class clk_reset_base_cfg extends config_base;

  rand int unsigned clk_period_ps    = 41667;  // ~24.0 MHz
  rand int unsigned duty_cycle_pct   = 50;
  rand int unsigned jitter_ps        = 0;
  rand int unsigned rst_assert_cycles = `SERDESPHY_MIN_RESET_CYCLES;

  constraint c_period {
    clk_period_ps inside {[35_000 : 45_000]};
  }

  constraint c_duty {
    duty_cycle_pct inside {[45 : 55]};
  }

  constraint c_jitter {
    jitter_ps == 0;
  }

  constraint c_rst_assert {
    rst_assert_cycles inside {[10 : 20]};
  }

  `uvm_object_utils_begin(clk_reset_base_cfg)
    `uvm_field_int(clk_period_ps, UVM_ALL_ON)
    `uvm_field_int(duty_cycle_pct, UVM_ALL_ON)
    `uvm_field_int(jitter_ps, UVM_ALL_ON)
    `uvm_field_int(rst_assert_cycles, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "clk_reset_base_cfg");
    super.new(name);
  endfunction

endclass : clk_reset_base_cfg
