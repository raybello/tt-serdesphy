
`ifndef SERDESPHY_ENV_PKG
`define SERDESPHY_ENV_PKG
// `include "uvm_macros.svh"

package serdesphy_env_pkg;

    import uvm_pkg::*;
    import sys_uvc_pkg::*;

    // Order
    //  transaction class
    //  sequence class
    //  sequencer class
    //  driver class
    //  monitor class
    //  agent class  
    //  coverage class
    //  scoreboard class
    //  environment class

    // I2C CONFIG
    // TX FIFO CONFIG
    // RX FIFO CONFIG

    `include "serdesphy_env_config.sv"
    `include "serdesphy_env.sv"

endpackage

`endif
