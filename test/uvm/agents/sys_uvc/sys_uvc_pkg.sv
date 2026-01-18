
package sys_uvc_pkg;

    `include "uvm_macros.svh"
    import uvm_pkg::*;

    `include "sys_trans.sv"
    `include "sys_sequencer.sv"
    `include "sys_config.sv"
    `include "sys_driver.sv"
    `include "sys_monitor.sv"
    `include "sys_agent.sv"

    `include "seqs/sys_init_seq.sv"

endpackage
