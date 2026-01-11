
`ifndef SERDESPHY_TEST_PKG
`define SERDESPHY_TEST_PKG
// `include "uvm_macros.svh"

package serdesphy_test_pkg;

    import uvm_pkg::*;
    import serdesphy_env_pkg::*;
    import serdesphy_seq_pkg::*;

    `include "serdesphy_base_test.sv"
    `include "serdesphy_init_test.sv"

endpackage

`endif
