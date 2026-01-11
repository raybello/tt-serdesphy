
`ifndef SERDESPHY_BASE_SEQ
`define SERDESPHY_BASE_SEQ

class serdesphy_base_seq extends uvm_sequence #(uvm_sequence_item, uvm_sequence_item);
    `uvm_object_utils(serdesphy_base_seq)

    serdesphy_env_config phy_env_cfg;
    sys_init_seq         sys_init_sq;

    function new(string name = "serdesphy_base_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info(get_type_name(), "SERDESPHY_BASE_SEQ BODY STARTED", UVM_LOW)

        if (phy_env_cfg == null)
            `uvm_fatal(get_type_name(), "phy_env_cfg is null")
        if (phy_env_cfg.sys_cfg == null)
            `uvm_fatal(get_type_name(), "phy_env_cfg.sys_cfg is null")
        if (phy_env_cfg.sys_cfg.seqr == null)
            `uvm_fatal(get_type_name(), "phy_env_cfg.sys_cfg.seqr is null")

        sys_init_sq = sys_init_seq::type_id::create("sys_init_sq");
        `uvm_info(get_type_name(), "Starting sys_init_seq", UVM_LOW)
        sys_init_sq.start(phy_env_cfg.sys_cfg.seqr);
        `uvm_info(get_type_name(), "sys_init_seq completed", UVM_LOW)
        #5us;
        `uvm_info(get_type_name(), "SERDESPHY_BASE_SEQ BODY COMPLETED", UVM_LOW)
    endtask

endclass
`endif
