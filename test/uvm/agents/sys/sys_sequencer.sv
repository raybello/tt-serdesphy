
`ifndef SYS_SEQUENCER
`define SYS_SEQUENCER

class sys_sequencer extends uvm_sequencer #(sys_trans, sys_trans);
    `uvm_component_utils(sys_sequencer)

    function new(string name = "sys_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass
`endif
