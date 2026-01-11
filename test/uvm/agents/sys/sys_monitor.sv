
`ifndef SYS_MONITOR
`define SYS_MONITOR

class sys_monitor extends uvm_monitor;
    `uvm_component_utils(sys_monitor)

    sys_config                     cfg;

    uvm_analysis_port #(sys_trans) ap;

    function new(string name = "sys_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
        collect_data();
    endtask

    task collect_data();
    endtask

endclass
`endif
