// PLL lock/unlock and VCO_TRIM register behavior (TEST_CHECKLIST.md
// category 4.2, CLK_004/006/007/008).
//
// Not covered here (documented, real behavioral-model limitations - see
// docs/implementation/pll/README.md section 5 "upgrade path for the
// behavioral model" and docs/implementation/01-spec-vs-implementation.md
// section 3.6): CLK_005 (verify PLL output is actually 240 MHz - the
// behavioral VCO is a fixed-period toggle with no way to observe its
// frequency from the digital pin interface), CLK_008's tuning-range claim
// beyond "the register accepts the full range" (VCO_TRIM has no effect on
// the behavioral VCO's frequency at all), and CLK_009 (jitter - not
// modeled). These need either a real circuit-level (SPICE) model or a
// richer behavioral Kvco model before they're meaningful to test here.

class pll_lock_test extends uvm_test;

  `uvm_component_utils(pll_lock_test)

  serdesphy_env      env;
  virtual system_if  vif;
  bit                last_got;

  function new(string name = "pll_lock_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "pll_lock_test: virtual interface not set via uvm_config_db")
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
    realtime          t0;
    uvm_reg_data_t    rdata;

    phase.raise_objection(this);

    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // CLK_004/006: PLL locks within 10us (docs/info.md 4.1: 8-10us
    // typ/max) and PLL_LOCK asserts.
    t0 = $realtime;
    wait_pll_lock(50_000, 1'b1);
    if (!last_got)
      `uvm_error("PLL_LOCK", "CLK_004/006: PLL_LOCK did not assert")
    else if (($realtime - t0) > 10_000)
      `uvm_error("PLL_LOCK", $sformatf("CLK_004: PLL_LOCK took %0.3fus, expected <=10us",
                                        ($realtime - t0) / 1000.0))
    else
      `uvm_info("PLL_LOCK",
                 $sformatf("CLK_004/006: PLL_LOCK asserted after %0.3fus - within spec", ($realtime - t0) / 1000.0),
                 UVM_LOW)

    // CLK_007: PLL_LOCK de-asserts on reset. serdesphy_pll_ctrl.v holds
    // lock through up to UNLOCK_COUNT=240 cycles (10us @ 24MHz) of
    // hysteresis before actually dropping it, so the timeout here needs
    // margin beyond that, not just beyond the I2C write's own latency.
    env.regmodel.set_pll_reset(1'b1, null);
    wait_pll_lock(30_000, 1'b0);
    if (!last_got)
      `uvm_error("PLL_LOCK", "CLK_007: PLL_LOCK did not de-assert after PLL_RST=1")
    else
      `uvm_info("PLL_LOCK", "CLK_007: PLL_LOCK de-asserted on PLL_RST=1 - OK", UVM_LOW)

    // Re-lock after releasing reset, confirming it can cycle more than
    // once (not a one-shot latch).
    env.regmodel.set_pll_reset(1'b0, null);
    t0 = $realtime;
    wait_pll_lock(50_000, 1'b1);
    if (!last_got)
      `uvm_error("PLL_LOCK", "PLL_LOCK did not re-assert after releasing PLL_RST a second time")
    else
      `uvm_info("PLL_LOCK",
                 $sformatf("PLL_LOCK re-locked after %0.3fus - OK", ($realtime - t0) / 1000.0), UVM_LOW)

    // CLK_008 (partial - register acceptance only, see header comment):
    // VCO_TRIM sweep 0x0 to 0xF, confirming the register accepts and
    // holds every documented value (docs/info.md 5.5 table) without
    // upsetting PLL_LOCK.
    for (int unsigned trim = 0; trim <= 4'hF; trim++) begin
      env.regmodel.write_csr("pll_config", "vco_trim", trim[3:0], null);
      env.regmodel.read_csr("pll_config", "vco_trim", rdata, null);
      if (rdata != trim)
        `uvm_error("PLL_LOCK", $sformatf("CLK_008: VCO_TRIM=0x%0h readback 0x%0h", trim, rdata))
    end
    #(1us);
    if (!vif.pll_lock)
      `uvm_error("PLL_LOCK", "CLK_008: PLL_LOCK dropped after sweeping VCO_TRIM through its full range")
    else
      `uvm_info("PLL_LOCK", "CLK_008: VCO_TRIM 0x0-0xF all accepted, PLL_LOCK held throughout - OK", UVM_LOW)

    phase.drop_objection(this);
  endtask : run_phase

endclass : pll_lock_test
