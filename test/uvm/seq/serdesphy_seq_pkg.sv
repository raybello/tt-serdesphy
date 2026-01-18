
`ifndef SERDESPHY_SEQ_PKG
`define SERDESPHY_SEQ_PKG
// `include "uvm_macros.svh"

package serdesphy_seq_pkg;

    import uvm_pkg::*;

    import sys_uvc_pkg::*;
    import serdesphy_env_pkg::*;

    `include "serdesphy_base_seq.sv"
    `include "serdesphy_init_csr_seq.sv"

endpackage

`endif
