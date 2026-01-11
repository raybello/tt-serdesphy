
`ifndef SERDESPHY_BASE_SEQ
`define SERDESPHY_BASE_SEQ

class serdesphy_base_seq extends uvm_sequence #(uvm_sequence_item, uvm_sequence_item);
    `uvm_object_utils(serdesphy_base_seq)

    serdesphy_env_config phy_env_cfg;
    sys_init_seq         sys_init_sq;

    function new(string name = "serdesphy_base_seq");
        super.new(name);
    endfunction

    task body();
        sys_init_sq = sys_init_seq::type_id::create("sys_init_sq");
        sys_init_sq.start(phy_env_cfg.sys_cfg.seqr);
        #5us;
    endtask

endclass
`endif
