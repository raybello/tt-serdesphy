// Brings the system up then exercises RAL frontdoor read/write
// (through i2c_agent) on a handful of RW registers, checking the
// I2C readback against what was written. Uses the reg_model's
// name-based write_csr()/read_csr() convenience API for individual
// fields (which check their own status internally), and the plain
// register write()/read() for whole-byte checks.

class csr_rdwr_test extends uvm_test;

  `uvm_component_utils(csr_rdwr_test)

  serdesphy_env env;

  function new(string name = "csr_rdwr_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    system_init_vseq init_seq;
    uvm_status_e      status;
    uvm_reg_data_t     rdata;

    phase.raise_objection(this);

    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // TX_CONFIG: enable TX + PRBS, field by field via write_csr/read_csr.
    env.regmodel.write_csr("tx_config", "tx_en", 1'b1, null);
    env.regmodel.write_csr("tx_config", "tx_prbs_en", 1'b1, null);

    env.regmodel.read_csr("tx_config", "tx_en", rdata, null);
    if (rdata != 1'h1)
      `uvm_error("CSR_RDWR", $sformatf("tx_config.tx_en readback mismatch: exp=1 got=%0d", rdata))

    env.regmodel.read_csr("tx_config", "tx_prbs_en", rdata, null);
    if (rdata != 1'h1)
      `uvm_error("CSR_RDWR",
                 $sformatf("tx_config.tx_prbs_en readback mismatch: exp=1 got=%0d", rdata))

    // DATA_SELECT: select FIFO on RX (whole-register write/read).
    env.regmodel.data_select.write(status, 8'h02, UVM_FRONTDOOR, env.regmodel.csr_map, null);
    env.regmodel.data_select.read(status, rdata, UVM_FRONTDOOR, env.regmodel.csr_map, null);
    if (rdata[1:0] != 2'h2)
      `uvm_error("CSR_RDWR",
                 $sformatf("DATA_SELECT readback mismatch: exp=0x2 got=0x%0h", rdata[1:0]))

    // DEBUG_ENABLE
    env.regmodel.write_csr("debug_enable", "dbg_vctrl", 1'b1, null);
    env.regmodel.write_csr("debug_enable", "dbg_pd", 1'b1, null);
    env.regmodel.read_csr("debug_enable", "dbg_vctrl", rdata, null);
    if (rdata != 1'h1)
      `uvm_error("CSR_RDWR",
                 $sformatf("debug_enable.dbg_vctrl readback mismatch: exp=1 got=%0d", rdata))
    env.regmodel.read_csr("debug_enable", "dbg_pd", rdata, null);
    if (rdata != 1'h1)
      `uvm_error("CSR_RDWR",
                 $sformatf("debug_enable.dbg_pd readback mismatch: exp=1 got=%0d", rdata))

    // STATUS is read-only - just log it.
    env.regmodel.read_csr("status", "pll_lock", rdata, null);
    `uvm_info("CSR_RDWR", $sformatf("STATUS.pll_lock = %0d", rdata), UVM_LOW)

    #5us;

    phase.drop_objection(this);
  endtask : run_phase

endclass : csr_rdwr_test
