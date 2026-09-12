// Bus adapter: uvm_reg_bus_op <-> i2c_tr. Each register access
// becomes exactly one I2C byte read or write through i2c_agent's
// sequencer (see agents/i2c_agent). Kept out of ral_pkg since it
// depends on i2c_tr (an agent transaction, not a RAL type); included
// into serdesphy_pkg after i2c_agent's classes.

class csr2i2c_adapter extends uvm_reg_adapter;

  `uvm_object_utils(csr2i2c_adapter)

  function new(string name = "csr2i2c_adapter");
    super.new(name);
    provides_responses   = 0;
    supports_byte_enable = 0;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    i2c_tr tr = i2c_tr::type_id::create("tr");
    tr.reg_addr = rw.addr[7:0];
    if (rw.kind == UVM_WRITE) begin
      tr.kind  = I2C_WRITE_REG;
      tr.wdata = rw.data[7:0];
    end else begin
      tr.kind = I2C_READ_REG;
    end
    return tr;
  endfunction : reg2bus

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    i2c_tr tr;
    if (!$cast(tr, bus_item))
      `uvm_fatal("CSR2I2C", "bus_item is not an i2c_tr")

    rw.kind   = (tr.kind == I2C_WRITE_REG) ? UVM_WRITE : UVM_READ;
    rw.addr   = tr.reg_addr;
    rw.data   = (tr.kind == I2C_WRITE_REG) ? tr.wdata : tr.rdata;
    rw.status = tr.status ? UVM_IS_OK : UVM_NOT_OK;
  endfunction : bus2reg

endclass : csr2i2c_adapter
