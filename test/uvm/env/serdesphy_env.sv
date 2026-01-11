`ifndef SERDESPHY_ENV
`define SERDESPHY_ENV

class serdesphy_env extends uvm_env;

    //---------------------------------------
    // agent and scoreboard instance
    //---------------------------------------
    //   mem_agent      mem_agnt;
    //   mem_scoreboard mem_scb;
    // serdesphy_sequencer sequencer;

    serdesphy_env_config phy_env_cfg;
    sys_agent            sys_agt;


    `uvm_component_utils(serdesphy_env)

    //---------------------------------------
    // constructor
    //---------------------------------------
    function new(string name = "serdesphy_env", uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //---------------------------------------
    // build_phase - crate the components
    //---------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sys_agt     = sys_agent::type_id::create("sys_agt", this);
        sys_agt.cfg = phy_env_cfg.sys_cfg;
        // mem_agnt = mem_agent::type_id::create("mem_agnt", this);
        // mem_scb  = mem_scoreboard::type_id::create("mem_scb", this);
        // sequencer = serdesphy_sequencer::type_id::create("sequencer", this);
    endfunction : build_phase

    //---------------------------------------
    // connect_phase - connecting monitor and scoreboard port
    //---------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // mem_agnt.monitor.item_collected_port.connect(mem_scb.item_collected_export);
    endfunction : connect_phase

endclass : serdesphy_env
`endif