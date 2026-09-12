// One CSR access over the I2C bus (see docs/info.md section 6.2 for
// the wire format): a byte write or a byte read at a register
// address. `status` is filled in by the driver: 1 = both address and
// data phases were ACKed by the DUT, 0 = a NACK was seen (e.g. wrong
// device address).

typedef enum {
  I2C_WRITE_REG,
  I2C_READ_REG
} i2c_kind_e;

class i2c_tr extends uvm_sequence_item;

  rand i2c_kind_e   kind;
  rand bit [7:0]    reg_addr;
  rand bit [7:0]    wdata;
  bit    [7:0]      rdata;
  bit               status;  // 1 = ok (ACKed), 0 = NACKed

  `uvm_object_utils_begin(i2c_tr)
    `uvm_field_enum(i2c_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(reg_addr, UVM_ALL_ON)
    `uvm_field_int(wdata, UVM_ALL_ON)
    `uvm_field_int(rdata, UVM_ALL_ON)
    `uvm_field_int(status, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i2c_tr");
    super.new(name);
  endfunction

endclass : i2c_tr
