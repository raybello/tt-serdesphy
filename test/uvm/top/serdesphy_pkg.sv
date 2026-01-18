
`ifndef SERDESPHY_PKG
`define SERDESPHY_PKG
`include "uvm_macros.svh"

package serdesphy_pkg;

    import uvm_pkg::*;

    import sys_uvc_pkg::*;
    import serdesphy_env_pkg::*; // Import the package instead of including it
    import serdesphy_test_pkg::*;
    

    // `include "dff_sequence_item.sv"  // transaction class
    // `include "dff_sequence.sv"  // sequence class
    // `include "dff_sequencer.sv"  // sequencer class
    // `include "dff_driver.sv"  // driver class
    // `include "dff_monitor.sv"  // monitor class
    // `include "dff_agent.sv"  // agent class  
    // `include "dff_coverage.sv"  // coverage class
    // `include "dff_scoreboard.sv"  // scoreboard class

    // `include "env/serdesphy_env_pkg.sv"  // environment class
    // `include "tests/serdesphy_test_pkg.sv"

endpackage

`endif
