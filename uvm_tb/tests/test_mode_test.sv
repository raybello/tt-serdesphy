// TEST_MODE pin propagation (TEST_CHECKLIST.md category 8, TM_001/003).
//
// TM_002 (serializer bypass in test mode) is not covered here: per
// docs/implementation/01-spec-vs-implementation.md, serdesphy_pma.v's
// serializer_bypass input is never connected to anything in the TX
// path (a dead port) - TEST_MODE currently has no effect on TX
// behavior at all, only on RX (via serdesphy_deserializer_if.v's
// deserializer_bypass). That gap is tracked in the audit doc, not
// re-litigated here.
//
// Verified via a white-box hierarchical reference into
// serdesphy_deserializer_if (the only place TEST_MODE's effect is
// actually implemented) rather than through vif, since system_if does
// not expose internal PMA-interface signals - this is a Verilator/UVM
// hierarchical dotted-path probe of a real DUT signal, not a
// duplicate/parallel model of it.

class test_mode_test extends uvm_test;

  `uvm_component_utils(test_mode_test)

  serdesphy_env      env;
  virtual system_if  vif;

  function new(string name = "test_mode_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "test_mode_test: virtual interface not set via uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    system_init_vseq init_seq;
    phy_set_config_seq cfg_seq;

    phase.raise_objection(this);

    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h03, null);  // RX_EN=1, RX_FIFO_EN=1

    // TM_001: TEST_MODE (ui_in[7]) reaches serdesphy_deserializer_if's
    // deserializer_bypass input as-is.
    cfg_seq          = phy_set_config_seq::type_id::create("test_mode_off");
    cfg_seq.lpbk_en   = 1'b1;
    cfg_seq.test_mode = 1'b0;
    cfg_seq.start(env.vseqr.phy_io_sqr);
    #(1us);
    if (tb_top.u_system.dut.u_top.u_deserializer_if.deserializer_bypass !== 1'b0)
      `uvm_error("TEST_MODE", "TM_001: deserializer_bypass should be 0 when TEST_MODE=0")
    else
      `uvm_info("TEST_MODE", "TM_001: TEST_MODE=0 -> deserializer_bypass=0 - OK", UVM_LOW)

    cfg_seq           = phy_set_config_seq::type_id::create("test_mode_on");
    cfg_seq.lpbk_en   = 1'b1;
    cfg_seq.test_mode = 1'b1;
    cfg_seq.start(env.vseqr.phy_io_sqr);
    #(1us);
    if (tb_top.u_system.dut.u_top.u_deserializer_if.deserializer_bypass !== 1'b1)
      `uvm_error("TEST_MODE", "TM_001: deserializer_bypass should be 1 when TEST_MODE=1")
    else
      `uvm_info("TEST_MODE", "TM_001: TEST_MODE=1 -> deserializer_bypass=1 - OK", UVM_LOW)

    // TM_003: in bypass, rx_serial_valid is forced to a constant 1
    // (docs/implementation Finding 2.2's deserializer_if fix) instead of
    // depending on the interface's own enable/lock sequencing FSM -
    // verified directly against the RTL's documented bypass expression.
    if (tb_top.u_system.dut.u_top.u_deserializer_if.rx_serial_valid !== 1'b1)
      `uvm_error("TEST_MODE", "TM_003: rx_serial_valid should be forced to 1 in deserializer bypass mode")
    else
      `uvm_info("TEST_MODE", "TM_003: deserializer bypass forces rx_serial_valid=1 - OK", UVM_LOW)

    phase.drop_objection(this);
  endtask : run_phase

endclass : test_mode_test
