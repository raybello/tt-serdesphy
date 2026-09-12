// Binds the passive checkers onto every system_if instance, so any
// testbench that instantiates system_if automatically gets clock and
// reset checking without system.sv having to know about it.

bind system_if clk_checker   u_clk_checker (.clk(clk_ref_24m), .rst_n(dut_rst_n));
bind system_if reset_checker u_reset_checker (.clk(clk_ref_24m), .rst_n(dut_rst_n));
