// Register definitions: one uvm_reg subclass per CSR, with its
// fields laid out per docs/info.md section 5 and
// src/digital/csr/serdesphy_registerInterface.v. csr_reg_model.sv
// assembles these into the address map and adds the convenience
// read/write helpers.
//
// NOTE: docs/info.md lists non-zero power-on defaults for PLL_CONFIG
// (0x68: VCO_TRIM=0x8, CP_CURRENT=0x2, PLL_RST=1) and CDR_CONFIG
// (0x14: CDR_GAIN=0x4, CDR_RST=1), but serdesphy_registerInterface.v
// actually resets both registers to 8'h00. The reset values below
// match the RTL (what the DUT really does on reset) so that RAL
// reset-value checks agree with simulation; this datasheet/RTL
// mismatch is worth flagging separately.

class phy_enable_reg extends uvm_reg;
  rand uvm_reg_field phy_en;
  rand uvm_reg_field iso_en;
  uvm_reg_field      rsvd;

  `uvm_object_utils(phy_enable_reg)

  function new(string name = "phy_enable_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    phy_en = uvm_reg_field::type_id::create("phy_en");
    iso_en = uvm_reg_field::type_id::create("iso_en");
    rsvd   = uvm_reg_field::type_id::create("rsvd");
    phy_en.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    iso_en.configure(this, 1, 1, "RW", 0, 1'b1, 1, 1, 0);
    rsvd.configure(this, 6, 2, "RO", 0, 6'h0, 1, 0, 0);
  endfunction
endclass : phy_enable_reg

class tx_config_reg extends uvm_reg;
  rand uvm_reg_field tx_en;
  rand uvm_reg_field tx_fifo_en;
  rand uvm_reg_field tx_prbs_en;
  rand uvm_reg_field tx_idle;
  uvm_reg_field      rsvd;

  `uvm_object_utils(tx_config_reg)

  function new(string name = "tx_config_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    tx_en      = uvm_reg_field::type_id::create("tx_en");
    tx_fifo_en = uvm_reg_field::type_id::create("tx_fifo_en");
    tx_prbs_en = uvm_reg_field::type_id::create("tx_prbs_en");
    tx_idle    = uvm_reg_field::type_id::create("tx_idle");
    rsvd       = uvm_reg_field::type_id::create("rsvd");
    tx_en.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    tx_fifo_en.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
    tx_prbs_en.configure(this, 1, 2, "RW", 0, 1'b0, 1, 1, 0);
    tx_idle.configure(this, 1, 3, "RW", 0, 1'b0, 1, 1, 0);
    rsvd.configure(this, 4, 4, "RW", 0, 4'h0, 1, 0, 0);
  endfunction
endclass : tx_config_reg

class rx_config_reg extends uvm_reg;
  rand uvm_reg_field rx_en;
  rand uvm_reg_field rx_fifo_en;
  rand uvm_reg_field rx_prbs_chk_en;
  rand uvm_reg_field rx_align_rst;
  uvm_reg_field      rsvd;

  `uvm_object_utils(rx_config_reg)

  function new(string name = "rx_config_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rx_en          = uvm_reg_field::type_id::create("rx_en");
    rx_fifo_en     = uvm_reg_field::type_id::create("rx_fifo_en");
    rx_prbs_chk_en = uvm_reg_field::type_id::create("rx_prbs_chk_en");
    rx_align_rst   = uvm_reg_field::type_id::create("rx_align_rst");
    rsvd           = uvm_reg_field::type_id::create("rsvd");
    rx_en.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    rx_fifo_en.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
    rx_prbs_chk_en.configure(this, 1, 2, "RW", 0, 1'b0, 1, 1, 0);
    rx_align_rst.configure(this, 1, 3, "RW", 0, 1'b0, 1, 1, 0);
    rsvd.configure(this, 4, 4, "RW", 0, 4'h0, 1, 0, 0);
  endfunction
endclass : rx_config_reg

class data_select_reg extends uvm_reg;
  rand uvm_reg_field tx_data_sel;
  rand uvm_reg_field rx_data_sel;
  uvm_reg_field      rsvd;

  `uvm_object_utils(data_select_reg)

  function new(string name = "data_select_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    tx_data_sel = uvm_reg_field::type_id::create("tx_data_sel");
    rx_data_sel = uvm_reg_field::type_id::create("rx_data_sel");
    rsvd        = uvm_reg_field::type_id::create("rsvd");
    tx_data_sel.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    rx_data_sel.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
    rsvd.configure(this, 6, 2, "RW", 0, 6'h0, 1, 0, 0);
  endfunction
endclass : data_select_reg

class pll_config_reg extends uvm_reg;
  rand uvm_reg_field vco_trim;
  rand uvm_reg_field cp_current;
  rand uvm_reg_field pll_rst;
  rand uvm_reg_field pll_bypass;

  `uvm_object_utils(pll_config_reg)

  function new(string name = "pll_config_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    vco_trim   = uvm_reg_field::type_id::create("vco_trim");
    cp_current = uvm_reg_field::type_id::create("cp_current");
    pll_rst    = uvm_reg_field::type_id::create("pll_rst");
    pll_bypass = uvm_reg_field::type_id::create("pll_bypass");
    // RTL resets the whole byte to 0x00 (see file header note above).
    vco_trim.configure(this, 4, 0, "RW", 0, 4'h0, 1, 1, 0);
    cp_current.configure(this, 2, 4, "RW", 0, 2'h0, 1, 1, 0);
    pll_rst.configure(this, 1, 6, "RW", 0, 1'b0, 1, 1, 0);
    pll_bypass.configure(this, 1, 7, "RW", 0, 1'b0, 1, 1, 0);
  endfunction
endclass : pll_config_reg

class cdr_config_reg extends uvm_reg;
  rand uvm_reg_field cdr_gain;
  rand uvm_reg_field cdr_fast_lock;
  rand uvm_reg_field cdr_rst;
  uvm_reg_field      rsvd;

  `uvm_object_utils(cdr_config_reg)

  function new(string name = "cdr_config_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    cdr_gain      = uvm_reg_field::type_id::create("cdr_gain");
    cdr_fast_lock = uvm_reg_field::type_id::create("cdr_fast_lock");
    cdr_rst       = uvm_reg_field::type_id::create("cdr_rst");
    rsvd          = uvm_reg_field::type_id::create("rsvd");
    // RTL resets the whole byte to 0x00 (see file header note above).
    cdr_gain.configure(this, 3, 0, "RW", 0, 3'h0, 1, 1, 0);
    cdr_fast_lock.configure(this, 1, 3, "RW", 0, 1'b0, 1, 1, 0);
    cdr_rst.configure(this, 1, 4, "RW", 0, 1'b0, 1, 1, 0);
    rsvd.configure(this, 3, 5, "RW", 0, 3'h0, 1, 0, 0);
  endfunction
endclass : cdr_config_reg

class status_reg extends uvm_reg;
  uvm_reg_field pll_lock;
  uvm_reg_field cdr_lock;
  uvm_reg_field tx_fifo_full;
  uvm_reg_field tx_fifo_empty;
  uvm_reg_field rx_fifo_full;
  uvm_reg_field rx_fifo_empty;
  uvm_reg_field prbs_err;
  uvm_reg_field fifo_err;

  `uvm_object_utils(status_reg)

  function new(string name = "status_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    pll_lock      = uvm_reg_field::type_id::create("pll_lock");
    cdr_lock      = uvm_reg_field::type_id::create("cdr_lock");
    tx_fifo_full  = uvm_reg_field::type_id::create("tx_fifo_full");
    tx_fifo_empty = uvm_reg_field::type_id::create("tx_fifo_empty");
    rx_fifo_full  = uvm_reg_field::type_id::create("rx_fifo_full");
    rx_fifo_empty = uvm_reg_field::type_id::create("rx_fifo_empty");
    prbs_err      = uvm_reg_field::type_id::create("prbs_err");
    fifo_err      = uvm_reg_field::type_id::create("fifo_err");
    pll_lock.configure(this, 1, 0, "RO", 1, 1'b0, 1, 0, 0);
    cdr_lock.configure(this, 1, 1, "RO", 1, 1'b0, 1, 0, 0);
    tx_fifo_full.configure(this, 1, 2, "RO", 1, 1'b0, 1, 0, 0);
    tx_fifo_empty.configure(this, 1, 3, "RO", 1, 1'b1, 1, 0, 0);
    rx_fifo_full.configure(this, 1, 4, "RO", 1, 1'b0, 1, 0, 0);
    rx_fifo_empty.configure(this, 1, 5, "RO", 1, 1'b1, 1, 0, 0);
    prbs_err.configure(this, 1, 6, "RO", 1, 1'b0, 1, 0, 0);
    fifo_err.configure(this, 1, 7, "RO", 1, 1'b0, 1, 0, 0);
  endfunction
endclass : status_reg

class debug_enable_reg extends uvm_reg;
  rand uvm_reg_field dbg_vctrl;
  rand uvm_reg_field dbg_pd;
  rand uvm_reg_field dbg_fifo;
  uvm_reg_field      rsvd;

  `uvm_object_utils(debug_enable_reg)

  function new(string name = "debug_enable_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    dbg_vctrl = uvm_reg_field::type_id::create("dbg_vctrl");
    dbg_pd    = uvm_reg_field::type_id::create("dbg_pd");
    dbg_fifo  = uvm_reg_field::type_id::create("dbg_fifo");
    rsvd      = uvm_reg_field::type_id::create("rsvd");
    dbg_vctrl.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    dbg_pd.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
    dbg_fifo.configure(this, 1, 2, "RW", 0, 1'b0, 1, 1, 0);
    rsvd.configure(this, 5, 3, "RW", 0, 5'h0, 1, 0, 0);
  endfunction
endclass : debug_enable_reg
