// Register model: assembles the register classes from ral.sv into
// the CSR address map, and adds convenience tasks for the accesses
// tests/vseqs do most often (PHY/PLL/CDR enable, status polling,
// name-based field/address access) so callers don't have to spell
// out uvm_reg field paths + map + adapter plumbing, or check status
// themselves, every time.
//
// Every convenience task takes an optional trailing `parent` (the
// calling sequence, so the frontdoor item is attributed to it) and
// checks the underlying uvm_reg status itself, raising `uvm_error`
// on anything other than UVM_IS_OK - callers don't need their own
// uvm_status_e output to check.

class serdesphy_reg_block extends uvm_reg_block;

  rand phy_enable_reg   phy_enable;
  rand tx_config_reg    tx_config;
  rand rx_config_reg    rx_config;
  rand data_select_reg  data_select;
  rand pll_config_reg   pll_config;
  rand cdr_config_reg   cdr_config;
  status_reg            status;
  rand debug_enable_reg debug_enable;

  uvm_reg_map csr_map;

  `uvm_object_utils(serdesphy_reg_block)

  function new(string name = "serdesphy_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    phy_enable   = phy_enable_reg::type_id::create("phy_enable");
    tx_config    = tx_config_reg::type_id::create("tx_config");
    rx_config    = rx_config_reg::type_id::create("rx_config");
    data_select  = data_select_reg::type_id::create("data_select");
    pll_config   = pll_config_reg::type_id::create("pll_config");
    cdr_config   = cdr_config_reg::type_id::create("cdr_config");
    status       = status_reg::type_id::create("status");
    debug_enable = debug_enable_reg::type_id::create("debug_enable");

    phy_enable.configure(this, null, "");
    tx_config.configure(this, null, "");
    rx_config.configure(this, null, "");
    data_select.configure(this, null, "");
    pll_config.configure(this, null, "");
    cdr_config.configure(this, null, "");
    status.configure(this, null, "");
    debug_enable.configure(this, null, "");

    phy_enable.build();
    tx_config.build();
    rx_config.build();
    data_select.build();
    pll_config.build();
    cdr_config.build();
    status.build();
    debug_enable.build();

    csr_map = create_map("csr_map", 0, 1, UVM_LITTLE_ENDIAN);
    csr_map.add_reg(phy_enable, system_pkg::REG_PHY_ENABLE, "RW");
    csr_map.add_reg(tx_config, system_pkg::REG_TX_CONFIG, "RW");
    csr_map.add_reg(rx_config, system_pkg::REG_RX_CONFIG, "RW");
    csr_map.add_reg(data_select, system_pkg::REG_DATA_SELECT, "RW");
    csr_map.add_reg(pll_config, system_pkg::REG_PLL_CONFIG, "RW");
    csr_map.add_reg(cdr_config, system_pkg::REG_CDR_CONFIG, "RW");
    csr_map.add_reg(status, system_pkg::REG_STATUS, "RO");
    csr_map.add_reg(debug_enable, system_pkg::REG_DEBUG_ENABLE, "RW");

    lock_model();
  endfunction : build

  // Checks a uvm_reg_bus_op status, raising `uvm_error` (tagged with
  // `what`, e.g. "tx_config.tx_en read") on anything but UVM_IS_OK.
  // Returns 1 on success, 0 on failure, so callers that need to bail
  // out early can `if (!check_status(...)) return;`.
  local function bit check_status(uvm_status_e status, string what);
    if (status != UVM_IS_OK) begin
      `uvm_error("CSR_REG_MODEL", $sformatf("%s failed (status=%s)", what, status.name()))
      return 1'b0;
    end
    return 1'b1;
  endfunction : check_status

  // --------------------------------------------------------------
  // PHY_ENABLE / PLL_CONFIG / CDR_CONFIG single-bit convenience
  // accessors. These read-modify-write the whole register rather than
  // going through uvm_reg_field::write() with UVM_FRONTDOOR: our bus
  // (I2C) can only move a whole byte at a time, so a 1-bit-wide field
  // can never be "individually accessible" and field.write() would
  // just fall back to the same read-modify-write itself - doing it
  // explicitly here avoids the (harmless but noisy) UVM_WARNING that
  // fallback prints on every call.
  // --------------------------------------------------------------
  virtual task automatic enable_phy(input bit en, input uvm_sequence_base parent = null);
    uvm_status_e   status_o;
    uvm_reg_data_t data;
    phy_enable.read(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    if (!check_status(status_o, "phy_enable read")) return;
    data[0] = en;
    phy_enable.write(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    void'(check_status(status_o, "phy_enable write"));
  endtask : enable_phy

  virtual task automatic set_isolation(input bit iso, input uvm_sequence_base parent = null);
    uvm_status_e   status_o;
    uvm_reg_data_t data;
    phy_enable.read(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    if (!check_status(status_o, "phy_enable read")) return;
    data[1] = iso;
    phy_enable.write(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    void'(check_status(status_o, "phy_enable write"));
  endtask : set_isolation

  virtual task automatic set_pll_reset(input bit rst, input uvm_sequence_base parent = null);
    uvm_status_e   status_o;
    uvm_reg_data_t data;
    pll_config.read(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    if (!check_status(status_o, "pll_config read")) return;
    data[6] = rst;
    pll_config.write(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    void'(check_status(status_o, "pll_config write"));
  endtask : set_pll_reset

  virtual task automatic set_cdr_reset(input bit rst, input uvm_sequence_base parent = null);
    uvm_status_e   status_o;
    uvm_reg_data_t data;
    cdr_config.read(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    if (!check_status(status_o, "cdr_config read")) return;
    data[4] = rst;
    cdr_config.write(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    void'(check_status(status_o, "cdr_config write"));
  endtask : set_cdr_reset

  // --------------------------------------------------------------
  // STATUS polling
  // --------------------------------------------------------------
  virtual task automatic read_status(output uvm_reg_data_t status_val,
                                     input uvm_sequence_base parent = null);
    uvm_status_e status_o;
    status.read(status_o, status_val, UVM_FRONTDOOR, csr_map, parent);
    void'(check_status(status_o, "status read"));
  endtask : read_status

  // Polls STATUS until `field` reads as `exp_val`, or `timeout_ns`
  // elapses (0 = wait forever). Returns 1 on success, 0 on timeout.
  virtual task automatic poll_status_field(input uvm_reg_field field, input bit exp_val,
                                           input longint unsigned timeout_ns,
                                           output bit success,
                                           input uvm_sequence_base parent = null);
    uvm_reg_data_t   status_val;
    longint unsigned waited_ns = 0;
    success = 1'b0;
    forever begin
      read_status(status_val, parent);
      if (bit'(field.get_mirrored_value()) == exp_val) begin
        success = 1'b1;
        return;
      end
      if (timeout_ns != 0 && waited_ns >= timeout_ns) return;
      #(1us);
      waited_ns += 1000;
    end
  endtask : poll_status_field

  // --------------------------------------------------------------
  // Generic name-based field access, e.g.:
  //   regmodel.write_csr("tx_config", "tx_en", 1'b1, this);
  //   regmodel.read_csr("status", "pll_lock", val, this);
  // Read-modify-write on the whole register (same reasoning as the
  // single-bit accessors above: our bus can't move less than a byte).
  // --------------------------------------------------------------
  virtual task automatic write_csr(input string reg_name, input string field_name,
                                   input uvm_reg_data_t value,
                                   input uvm_sequence_base parent = null);
    uvm_reg        r;
    uvm_reg_field  f;
    uvm_status_e   status_o;
    uvm_reg_data_t data, mask;

    r = get_reg_by_name(reg_name);
    if (r == null)
      `uvm_fatal("CSR_REG_MODEL", $sformatf("No register named '%s'", reg_name))

    f = r.get_field_by_name(field_name);
    if (f == null)
      `uvm_fatal("CSR_REG_MODEL", $sformatf("Register '%s' has no field '%s'", reg_name, field_name))

    r.read(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    if (!check_status(status_o, {reg_name, ".", field_name, " read"})) return;

    mask = ((uvm_reg_data_t'(1) << f.get_n_bits()) - 1) << f.get_lsb_pos();
    data = (data & ~mask) | ((value << f.get_lsb_pos()) & mask);
    r.write(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    void'(check_status(status_o, {reg_name, ".", field_name, " write"}));
  endtask : write_csr

  virtual task automatic read_csr(input string reg_name, input string field_name,
                                  output uvm_reg_data_t value,
                                  input uvm_sequence_base parent = null);
    uvm_reg        r;
    uvm_reg_field  f;
    uvm_status_e   status_o;
    uvm_reg_data_t data;

    r = get_reg_by_name(reg_name);
    if (r == null)
      `uvm_fatal("CSR_REG_MODEL", $sformatf("No register named '%s'", reg_name))

    f = r.get_field_by_name(field_name);
    if (f == null)
      `uvm_fatal("CSR_REG_MODEL", $sformatf("Register '%s' has no field '%s'", reg_name, field_name))

    r.read(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    if (!check_status(status_o, {reg_name, ".", field_name, " read"})) return;

    value = (data >> f.get_lsb_pos()) & ((uvm_reg_data_t'(1) << f.get_n_bits()) - 1);
  endtask : read_csr

  // --------------------------------------------------------------
  // Generic address-based access (e.g. for directed/random CSR
  // read-write tests that iterate over the whole map).
  // --------------------------------------------------------------
  virtual task automatic write_reg_by_addr(input system_pkg::csr_addr_e addr,
                                           input uvm_reg_data_t data,
                                           input uvm_sequence_base parent = null);
    uvm_status_e status_o;
    uvm_reg      r = csr_map.get_reg_by_offset(addr);
    if (r == null) `uvm_fatal("CSR_REG_MODEL", $sformatf("No register at address 0x%0h", addr))
    r.write(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    void'(check_status(status_o, $sformatf("addr 0x%0h write", addr)));
  endtask : write_reg_by_addr

  virtual task automatic read_reg_by_addr(input system_pkg::csr_addr_e addr,
                                          output uvm_reg_data_t data,
                                          input uvm_sequence_base parent = null);
    uvm_status_e status_o;
    uvm_reg      r = csr_map.get_reg_by_offset(addr);
    if (r == null) `uvm_fatal("CSR_REG_MODEL", $sformatf("No register at address 0x%0h", addr))
    r.read(status_o, data, UVM_FRONTDOOR, csr_map, parent);
    void'(check_status(status_o, $sformatf("addr 0x%0h read", addr)));
  endtask : read_reg_by_addr

endclass : serdesphy_reg_block
