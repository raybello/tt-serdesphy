
`ifndef SYS_INIT_SEQ
`define SYS_INIT_SEQ

class sys_init_seq extends uvm_sequence #(uvm_sequence_item, uvm_sequence_item);
    `uvm_object_utils(sys_init_seq)

    sys_trans txn, txn_clone;

    function new(string name = "sys_init_seq");
        super.new(name);
    endfunction

    task body();
        super.body();
        start_clk();
        assert_reset();
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
