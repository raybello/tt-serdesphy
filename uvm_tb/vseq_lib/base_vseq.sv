// Parent for every virtual sequence: runs on serdesphy_virtual_sequencer
// (so it can reach both clk_reset_sqr and i2c_sqr) and fetches the RAL
// model out of the config_db so subclasses can drive CSR accesses
// without each one having to look it up itself.

class base_vseq extends uvm_sequence #(uvm_sequence_item);

  `uvm_object_utils(base_vseq)
  `uvm_declare_p_sequencer(serdesphy_virtual_sequencer)

  serdesphy_reg_block regmodel;

  function new(string name = "base_vseq");
    super.new(name);
  endfunction

  virtual task pre_body();
    if (!uvm_config_db#(serdesphy_reg_block)::get(p_sequencer, "", "regmodel", regmodel))
      `uvm_fatal("BASE_VSEQ", "regmodel not found in config_db")
  endtask : pre_body

endclass : base_vseq
