// Single CSR read. Set .reg_addr before calling start(); result comes
// back in .rdata/.status.

class i2c_read_reg_seq extends uvm_sequence #(i2c_tr);

  `uvm_object_utils(i2c_read_reg_seq)

  rand bit [7:0] reg_addr;
  bit    [7:0]   rdata;
  bit            status;

  function new(string name = "i2c_read_reg_seq");
    super.new(name);
  endfunction

  task body();
    i2c_tr item = i2c_tr::type_id::create("item");
    start_item(item);
    item.kind     = I2C_READ_REG;
    item.reg_addr = reg_addr;
    finish_item(item);
    rdata  = item.rdata;
    status = item.status;
  endtask : body

endclass : i2c_read_reg_seq
