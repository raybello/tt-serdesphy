
`ifndef SYS_INIT_SEQ
`define SYS_INIT_SEQ

class sys_init_seq extends uvm_sequence #(sys_trans);
    `uvm_object_utils(sys_init_seq)

    sys_trans txn, txn_clone;

    function new(string name = "sys_init_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info(get_type_name(), "sys_init_seq body started", UVM_LOW)
        start_clk();
        `uvm_info(get_type_name(), "start_clk completed, calling assert_reset", UVM_LOW)
        assert_reset();
        `uvm_info(get_type_name(), "sys_init_seq body completed", UVM_LOW)
    endtask

    task start_clk();
        txn = new();

        txn.start_clk = 1;

        $cast(txn_clone, txn.clone());
        start_item(txn_clone);
        finish_item(txn_clone);
    endtask

    task assert_reset();
        txn = new();

        txn.assert_rst = 1;

        $cast(txn_clone, txn.clone());
        start_item(txn_clone);
        finish_item(txn_clone);
    endtask

endclass
`endif
