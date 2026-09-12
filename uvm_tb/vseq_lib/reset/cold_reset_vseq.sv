// Asserts reset, starts the reference clock, then deasserts reset
// after cfg.rst_assert_cycles clk_ref_24m cycles - the standard
// power-on sequence every test needs before touching CSRs.
// Set .cfg before start() to drive from clk_reset_base_cfg or
// clk_reset_full_cfg (falls back to nominal 24 MHz otherwise).

class cold_reset_vseq extends base_vseq;

  `uvm_object_utils(cold_reset_vseq)

  clk_reset_base_cfg cfg;

  function new(string name = "cold_reset_vseq");
    super.new(name);
  endfunction

  task body();
    clk_reset_assert_rst_seq   assert_seq;
    clk_reset_start_clk_seq    start_seq;
    clk_reset_deassert_rst_seq deassert_seq;

    assert_seq = clk_reset_assert_rst_seq::type_id::create("assert_seq");
    assert_seq.start(p_sequencer.clk_reset_sqr);

    start_seq     = clk_reset_start_clk_seq::type_id::create("start_seq");
    start_seq.cfg = cfg;
    start_seq.start(p_sequencer.clk_reset_sqr);

    deassert_seq     = clk_reset_deassert_rst_seq::type_id::create("deassert_seq");
    deassert_seq.cfg = cfg;
    deassert_seq.start(p_sequencer.clk_reset_sqr);

    // Releasing dut_rst_n does NOT make the I2C/CSR block usable yet:
    // serdesphy_csr_top (and therefore u_i2c_slave) is reset by
    // digital_reset_n, which comes from serdesphy_por's own internal
    // power-on-reset sequencer (src/digital/por/serdesphy_por.v), not
    // from dut_rst_n directly. That sequencer waits SUPPLY_STABLE_CYCLES
    // (48) after dut_rst_n releases, then walks seq_step through
    // RESET_HOLD_CYCLES (24) and two RELEASE_DELAY_CYCLES (12 each)
    // before asserting digital_reset_n - ~96 clk_ref_24m cycles of
    // latency, plus a few more for state-transition overhead and the
    // i2c_slave's own 2-stage reset synchronizer/debounce pipeline.
    // A caller that issues an I2C transaction right after dut_rst_n
    // releases (e.g. system_init_vseq -> csr_init_vseq, with no wait
    // of its own) races the DUT's internal reset still being asserted:
    // the master's START gets swallowed while u_i2c_slave.rst is still
    // high, so the transaction silently loses its first several bits
    // and NACKs (see i2c_driver's retry loop). 150 cycles clears the
    // full POR sequence with comfortable margin, including under
    // clk_reset_full_cfg's randomized (faster) clk_period_ps.
    #(150 * ((cfg != null) ? cfg.clk_period_ps : 41667) * 1ps);
  endtask : body

endclass : cold_reset_vseq
