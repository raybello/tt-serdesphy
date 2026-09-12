// Single CSR write. Set .reg_addr/.wdata before calling start().

class i2c_write_reg_seq extends uvm_sequence #(i2c_tr);

  `uvm_object_utils(i2c_write_reg_seq)

  rand bit [7:0] reg_addr;
  rand bit [7:0] wdata;
  bit            status;

  function new(string name = "i2c_write_reg_seq");
    super.new(name);
  endfunction

  task body();
    i2c_tr item = i2c_tr::type_id::create("item");
    start_item(item);
    item.kind     = I2C_WRITE_REG;
    item.reg_addr = reg_addr;
    item.wdata    = wdata;
    finish_item(item);
    status = item.status;
  endtask : body

endclass : i2c_write_reg_seq
