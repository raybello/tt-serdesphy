// Corner cases (TEST_CHECKLIST.md category 11): rapid back-to-back CSR
// writes (CC_003/004), enable/disable transitions during operation
// (CC_005), and PLL/CDR reset asserted mid-operation (CC_006).
//
// Not covered here: CC_001 (power-on with supplies not OK) and CC_002
// (reset during POR sequencing) would need system.sv's `ena` (tied
// statically to 1'b1, feeding dvdd_ok/avdd_ok - see src/project.v) to be
// independently controllable, which no existing agent currently
// provides; serdesphy_por.v's own state machine is already exercised
// indirectly by every test that runs cold_reset_vseq, but not with
// supplies deliberately toggled mid-sequence. CC_007 (mode changes
// during operation) overlaps with docs/info.md 5.2's DATA_SELECT/TX_EN
// interaction, itself only partially exercised - see
// tx_rx_loopback_test.sv's header comment on alignment re-acquisition
// under a source switch.

class corner_case_test extends uvm_test;

  `uvm_component_utils(corner_case_test)

  serdesphy_env      env;
  virtual system_if  vif;
  bit                last_got;

  function new(string name = "corner_case_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "corner_case_test: virtual interface not set via uvm_config_db")
  endfunction

  // Named fork block + `disable <name>`, not bare `disable fork` - see
  // docs/implementation/00-fixes-applied.md: a bare `disable fork`
  // terminates every descendant process of the calling process, not just
  // this block's own two branches.
  task automatic wait_pll_lock(input realtime timeout_ns, input bit exp_val);
    last_got = 1'b0;
    fork : pll_wait_blk
      begin
        wait (vif.pll_lock == exp_val);
        last_got = 1'b1;
      end
      begin
        #(timeout_ns * 1ns);
      end
    join_any
    disable pll_wait_blk;
  endtask : wait_pll_lock

  task run_phase(uvm_phase phase);
    system_init_vseq init_seq;
    uvm_reg_data_t    rdata;

    phase.raise_objection(this);

    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // CC_003/004: rapid back-to-back register writes and reads across
    // every RW register, no idle time between transactions - the I2C
    // slave's debounce/start-stop detection must keep up without
    // dropping or misrouting any of them.
    for (int unsigned i = 0; i < 20; i++) begin
      bit [7:0] val = 8'h01 << (i % 4);
      env.regmodel.write_reg_by_addr(system_pkg::REG_TX_CONFIG, val, null);
      env.regmodel.read_reg_by_addr(system_pkg::REG_TX_CONFIG, rdata, null);
      if (rdata != val)
        `uvm_error("CORNER", $sformatf("CC_003: rapid write/read %0d mismatch: wrote 0x%0h, read 0x%0h",
                                        i, val, rdata))
    end
    `uvm_info("CORNER", "CC_003/004: 20 back-to-back register write/read cycles completed", UVM_LOW)
    env.regmodel.write_reg_by_addr(system_pkg::REG_TX_CONFIG, 8'h00, null);

    // CC_005: enable/disable transitions during operation - toggle
    // PHY_EN off and back on several times while PLL is locked, and
    // confirm it recovers cleanly every time (not just once).
    for (int unsigned i = 0; i < 3; i++) begin
      wait_pll_lock(50_000, 1'b1);
      if (!last_got) begin
        `uvm_error("CORNER", $sformatf("CC_005: PLL_LOCK did not (re-)assert on enable/disable cycle %0d", i))
        continue;
      end
      env.regmodel.enable_phy(1'b0, null);
      wait_pll_lock(30_000, 1'b0);
      if (!last_got)
        `uvm_error("CORNER", $sformatf("CC_005: PLL_LOCK did not drop after PHY_EN=0 on cycle %0d", i))
      env.regmodel.enable_phy(1'b1, null);
    end
    wait_pll_lock(50_000, 1'b1);
    if (!last_got)
      `uvm_error("CORNER", "CC_005: PLL_LOCK did not re-assert after the final PHY_EN=1")
    else
      `uvm_info("CORNER", "CC_005: PHY_EN enable/disable cycled 3x, PLL recovered every time - OK", UVM_LOW)

    // CC_006: assert PLL_RST and CDR_RST while TX/RX are actively
    // configured (mid-"operation" from the CSR's point of view), then
    // release and confirm both recover.
    env.regmodel.write_reg_by_addr(system_pkg::REG_TX_CONFIG, 8'h05, null);  // TX_EN=1, TX_PRBS_EN=1
    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h05, null);  // RX_EN=1, RX_PRBS_CHK_EN=1
    #(5us);
    env.regmodel.set_pll_reset(1'b1, null);
    env.regmodel.set_cdr_reset(1'b1, null);
    wait_pll_lock(30_000, 1'b0);
    if (!last_got)
      `uvm_error("CORNER", "CC_006: PLL_LOCK did not drop after asserting PLL_RST mid-operation")
    if (vif.cdr_lock)
      `uvm_error("CORNER", "CC_006: CDR_LOCK still asserted after asserting CDR_RST mid-operation")
    env.regmodel.set_pll_reset(1'b0, null);
    env.regmodel.set_cdr_reset(1'b0, null);
    wait_pll_lock(50_000, 1'b1);
    if (!last_got)
      `uvm_error("CORNER", "CC_006: PLL_LOCK did not recover after releasing PLL_RST/CDR_RST")
    else
      `uvm_info("CORNER", "CC_006: PLL/CDR reset mid-operation recovered cleanly - OK", UVM_LOW)

    phase.drop_objection(this);
  endtask : run_phase

endclass : corner_case_test
