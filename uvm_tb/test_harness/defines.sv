// Global `define macros for the serdesphy UVM testbench.
//
// This file is a plain text-substitution header: it must be compiled
// (or `include`d) before any file that references these macros. It
// carries no module/interface/package of its own.

`ifndef SERDESPHY_DEFINES_SV
`define SERDESPHY_DEFINES_SV

// Nominal reference clock (matches the 24 MHz clock the DUT expects
// on ui_in[0]).
`define SERDESPHY_REF_CLK_FREQ_MHZ   24
`define SERDESPHY_REF_CLK_PERIOD_NS  41.667

// I2C (CSR) bus
`define SERDESPHY_I2C_DEV_ADDR       7'h42
`define SERDESPHY_I2C_NUM_REGS       8

// Minimum number of clk_ref_24m cycles the DUT needs reset asserted
// for (matches serdesphy_i2c_slave's `DEB_I2C_LEN` debounce window and
// leaves margin for the reset synchronizer chain).
`define SERDESPHY_MIN_RESET_CYCLES   10

// clk_checker / reset_checker sanity bounds. These are intentionally
// generous: they exist to catch a stuck/dead clock or a truncated
// reset pulse, not to pin down one exact operating point, since
// clk_reset_full_cfg legally drives a faster/jittery clock.
`define SERDESPHY_CLK_PERIOD_MIN_NS  4.0
`define SERDESPHY_CLK_PERIOD_MAX_NS  100.0
`define SERDESPHY_CLK_DUTY_MIN_PCT   30
`define SERDESPHY_CLK_DUTY_MAX_PCT   70

`endif // SERDESPHY_DEFINES_SV
