// PLL Configuration Class
// Randomizable configuration for PLL calibration testing
// Randomizes initial VCO trim value to verify calibration converges from any starting point

class pll_cfg extends uvm_object;

  `uvm_object_utils(pll_cfg)

  // Randomized initial VCO trim value
  // In real designs, this could be set to any value on power-up
  // Calibration must converge to optimal value from any starting point
  rand bit [3:0] initial_vco_trim;

  // Expected optimal trim value (for verification)
  // For 240 MHz target with our VCO model, optimal is around trim=8
  bit [3:0] expected_optimal_trim;

  // Calibration timeout (in us)
  real cal_timeout_us;

  // Constraints
  constraint c_initial_trim {
    // Allow full range - calibration should work from any starting point
    initial_vco_trim inside {[0:15]};
  }

  function new(string name = "pll_cfg");
    super.new(name);
    // Default values
    expected_optimal_trim = 4'h8;  // Mid-range, 240 MHz nominal
    cal_timeout_us = 200.0;         // Max 6 iterations × 20us settling
  endfunction

  function void do_print(uvm_printer printer);
    super.do_print(printer);
    printer.print_field("initial_vco_trim", initial_vco_trim, 4, UVM_HEX);
    printer.print_field("expected_optimal_trim", expected_optimal_trim, 4, UVM_HEX);
    printer.print_real("cal_timeout_us", cal_timeout_us);
  endfunction

endclass : pll_cfg
