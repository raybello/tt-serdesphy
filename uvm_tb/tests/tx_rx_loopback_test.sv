// End-to-end TX -> internal analog loopback -> RX data-integrity test,
// following docs/info.md section 8.1's own documented loopback procedure
// (steps 3-11: enable PHY, release PLL/CDR reset, enable TX+PRBS,
// release CDR reset, enable RX+PRBS check, poll CDR_LOCK, then monitor
// PRBS_ERR staying low) - TEST_CHECKLIST.md categories 4 (Clock/PLL), 6
// (RX Datapath: CDR), and 7 (Loopback). LPBK_EN defaults to 1 in
// phy_io_driver, so no explicit loopback-enable step is needed here.
//
// Also doubles as the regression test for
// docs/implementation/01-spec-vs-implementation.md Finding 2.1: it
// checks PLL_LOCK *before* touching TX_CONFIG/RX_CONFIG at all, exactly
// matching section 8.1's ordering (PLL_LOCK is polled in step 5, TX is
// only enabled in step 6) - if PLL_LOCK were still gated by TX_EN, this
// test would hang/timeout right there.
//
// Data integrity is checked via PRBS_ERR (docs/info.md 8.1 step 11:
// "Monitor STATUS[6] (PRBS_ERR should remain low)"), not by capturing
// and matching an exact FIFO nibble sequence: PRBS is what the datasheet
// itself specifies for loopback validation, generated and paced entirely
// inside the DUT at its own natural rate, which sidesteps a separate,
// deeper question this test does not attempt to answer - how robustly
// serdesphy_rx_top's Manchester-window alignment re-acquires under
// externally-host-paced, gapped FIFO traffic (its search now tries every
// bit phase rather than a single fixed one - see the "Serial input
// accumulation" block in serdesphy_rx_top.v - but getting a clean,
// reliably-reproducible byte-exact FIFO capture through a live UVM
// virtual-interface driver, on top of that, turned out to need more
// dedicated tuning than this test's scope; see
// docs/implementation/01-spec-vs-implementation.md Finding 2.2 addendum).
//
// Lock detection polls system_if.pll_lock/cdr_lock directly rather than
// through an I2C read of STATUS: a single I2C register read takes on the
// order of tens of us of simulated time (a full bit-banged
// START+ADDR+REGADDR+repeated-START+ADDR+READ+STOP transaction), which
// would dwarf and badly under-resolve the sub-100us lock-time specs this
// test is checking against.

class tx_rx_loopback_test extends uvm_test;

  `uvm_component_utils(tx_rx_loopback_test)

  serdesphy_env     env;
  virtual system_if vif;

  // wait_*() below write here rather than to task output ports:
  // SystemVerilog disallows writing an automatic task's output port
  // after a timing control has suspended it (IEEE 1800-2023 13.2.2),
  // which the fork/join_any + disable-fork timeout idiom does.
  bit last_got;

  function new(string name = "tx_rx_loopback_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "tx_rx_loopback_test: virtual interface not set via uvm_config_db")
  endfunction

  // Blocking wait-for-1 with a timeout: leaves last_got=0 if the signal
  // never went high within timeout_ns. Two dedicated tasks (rather than
  // one parameterized by a `bit` argument) because passing the signal by
  // value would just snapshot it once - `wait()` needs to see the live
  // vif signal, not a copy.
  // Named fork blocks + `disable <name>`, not bare `disable fork`: a bare
  // `disable fork` terminates every descendant process of the *calling*
  // process, not just the two branches of its own fork/join_any block -
  // if a caller ever runs one of these while a background fork of its own
  // is still active in the same process, `disable fork` silently kills
  // that unrelated background process too (see
  // docs/implementation/00-fixes-applied.md for the concrete case this
  // caused in fifo_loopback_test.sv).
  task automatic wait_pll_lock(input realtime timeout_ns);
    last_got = 1'b0;
    fork : pll_wait_blk
      begin
        wait (vif.pll_lock == 1'b1);
        last_got = 1'b1;
      end
      begin
        #(timeout_ns * 1ns);
      end
    join_any
    disable pll_wait_blk;
  endtask : wait_pll_lock

  task automatic wait_cdr_lock(input realtime timeout_ns);
    last_got = 1'b0;
    fork : cdr_wait_blk
      begin
        wait (vif.cdr_lock == 1'b1);
        last_got = 1'b1;
      end
      begin
        #(timeout_ns * 1ns);
      end
    join_any
    disable cdr_wait_blk;
  endtask : wait_cdr_lock

  // Watches vif.prbs_err for the whole duration; leaves last_got=1 if it
  // ever pulsed high (a real, sticky-until-clear-on-read error - see
  // docs/info.md 5.7), 0 if it stayed low for the full window.
  task automatic watch_for_prbs_err(input realtime window_ns);
    last_got = 1'b0;
    fork : prbs_watch_blk
      begin
        wait (vif.prbs_err == 1'b1);
        last_got = 1'b1;
      end
      begin
        #(window_ns * 1ns);
      end
    join_any
    disable prbs_watch_blk;
  endtask : watch_for_prbs_err

  task run_phase(uvm_phase phase);
    system_init_vseq init_seq;
    realtime          t0;

    phase.raise_objection(this);

    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // --- Finding 2.1 regression check ---
    // TX_CONFIG is still at its POR reset default (TX_EN=0) here -
    // system_init_vseq/csr_init_vseq never touch it. PLL_LOCK must still
    // assert (docs/info.md 4.1: lock time 8-10us typ/max; 50us budget
    // below gives generous margin for the reset/power-up lead-in).
    t0 = $realtime;
    wait_pll_lock(50_000);
    if (!last_got)
      `uvm_error("TXRX_LB",
                 "PLL_LOCK did not assert with TX_EN=0 (Finding 2.1 regression)")
    else
      `uvm_info("TXRX_LB",
                 $sformatf("PLL_LOCK asserted after %0.3fus with TX still disabled - Finding 2.1 OK",
                            ($realtime - t0) / 1000.0), UVM_LOW)

    // docs/info.md 8.1 steps 6-9: PRBS source on TX, PRBS check on RX,
    // both directions of DATA_SELECT don't matter for PRBS_ERR itself
    // (it's computed by the checker regardless of RX_DATA_SEL), so leave
    // DATA_SELECT at its reset default (0x00: TX_DATA_SEL=PRBS already).
    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h05, null);  // RX_EN=1, RX_PRBS_CHK_EN=1
    env.regmodel.write_reg_by_addr(system_pkg::REG_TX_CONFIG, 8'h05, null);  // TX_EN=1, TX_PRBS_EN=1

    // CDR_LOCK: docs/info.md 4.3 budgets up to 100us; give it margin.
    t0 = $realtime;
    wait_cdr_lock(600_000);
    if (!last_got) begin
      `uvm_error("TXRX_LB", "CDR_LOCK did not assert within 600us of loopback")
    end else begin
      `uvm_info("TXRX_LB",
                 $sformatf("CDR_LOCK asserted after %0.3fus", ($realtime - t0) / 1000.0), UVM_LOW)

      // docs/info.md 5.3: RX_ALIGN_RST resets the alignment FSM and PRBS
      // error counter - clears anything accumulated while the checker's
      // own LFSR was still resyncing to the incoming PRBS-7 sequence
      // during acquisition, giving a clean baseline for the "stays low"
      // check below.
      env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h0D, null);  // + RX_ALIGN_RST
      env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h05, null);  // release it
      #(5us);  // let the checker resync its LFSR post-reset

      // docs/info.md 8.1 step 11: "Monitor STATUS[6] (PRBS_ERR should
      // remain low)".
      watch_for_prbs_err(100_000);
      if (last_got)
        `uvm_error("TXRX_LB", "PRBS_ERR asserted during loopback monitoring window - data integrity failure")
      else
        `uvm_info("TXRX_LB", "PRBS_ERR stayed low for 100us of loopback traffic - data integrity OK", UVM_LOW)
    end

    phase.drop_objection(this);
  endtask : run_phase

endclass : tx_rx_loopback_test
