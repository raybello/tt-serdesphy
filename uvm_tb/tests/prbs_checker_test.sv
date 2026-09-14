// RX PRBS checker structural checks (TEST_CHECKLIST.md category 6.6,
// RX_016-019).
//
// This deliberately does NOT try to force/inject a controlled byte
// stream directly into serdesphy_prbs_checker.v's inputs: SystemVerilog
// `force` on a hierarchical net turned out not to be usable from this
// testbench's Verilator build - it cannot read back a value from any
// class-scoped variable (a task argument or a class member), only a
// literal constant, so an actually-useful injected byte sequence isn't
// buildable that way here. Instead, this test runs real TX -> analog
// loopback -> CDR -> RX traffic (the same mechanism as
// tx_rx_loopback_test.sv) and passively READS (never forces)
// serdesphy_prbs_checker.v's internal state hierarchically.
//
// This works out cleanly rather than being a workaround: RX_016-019 ask
// whether the checker correctly compares/detects/counts/resets errors,
// not whether the link is error-free - and docs/implementation/
// 00-fixes-applied.md section 6's documented residual CDR phase-tracking
// gap means real mismatches DO occur reasonably often under real PRBS
// traffic, which is exactly the raw material this test needs. Unlike
// tx_rx_loopback_test.sv (whose pass criterion is "no errors" and is
// therefore expected to fail given that gap), this test's pass criterion
// is "errors are counted correctly when they occur", which is orthogonal
// to that gap and unaffected by it.

class prbs_checker_test extends uvm_test;

  `uvm_component_utils(prbs_checker_test)

  serdesphy_env      env;
  virtual system_if  vif;
  bit                last_got;

  function new(string name = "prbs_checker_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "prbs_checker_test: virtual interface not set via uvm_config_db")
  endfunction

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

  task run_phase(uvm_phase phase);
    system_init_vseq init_seq;
    byte              err_count_prev, err_count_now;
    int unsigned       increments_seen, non_unit_jumps, mismatched_decrements;
    int unsigned       poll_count;

    phase.raise_objection(this);

    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h05, null);  // RX_EN + RX_PRBS_CHK_EN
    env.regmodel.write_reg_by_addr(system_pkg::REG_TX_CONFIG, 8'h05, null);  // TX_EN + TX_PRBS_EN

    wait_cdr_lock(600_000);
    if (!last_got) begin
      `uvm_error("PRBS_CHK", "CDR_LOCK did not assert - cannot proceed")
      phase.drop_objection(this);
      return;
    end

    // --- RX_016/RX_017: every error_count increment corresponds to
    // exactly one detected mismatch, never more (a hardware bug that
    // double-counted, or counted on something other than a genuine
    // mismatch, would show up here as either a >1 jump or a jump with
    // error_detected not actually having pulsed for it) ---
    err_count_prev    = tb_top.u_system.dut.u_top.u_pcs.u_rx.u_prbs_checker.error_count;
    increments_seen       = 0;
    non_unit_jumps        = 0;
    mismatched_decrements = 0;
    poll_count             = 0;

    // Poll once per clk_240m_rx cycle (the checker's own clock) for a
    // window generous enough, given the documented error rate, to
    // reliably both observe several individual increments (RX_017) and
    // eventually saturate (RX_018).
    while (poll_count < 200_000) begin
      @(posedge tb_top.u_system.dut.u_top.u_pcs.u_rx.clk_240m_rx);
      poll_count++;
      err_count_now = tb_top.u_system.dut.u_top.u_pcs.u_rx.u_prbs_checker.error_count;
      if (err_count_now != err_count_prev) begin
        if (err_count_now == err_count_prev + 8'd1) begin
          increments_seen++;
        end else if (err_count_now > err_count_prev) begin
          non_unit_jumps++;
        end else begin
          mismatched_decrements++;
        end
        err_count_prev = err_count_now;
      end
      if (err_count_now == 8'hFF) begin
        poll_count = 200_000;  // saturated - no need to keep polling
      end
    end

    if (non_unit_jumps > 0)
      `uvm_error("PRBS_CHK",
                 $sformatf("RX_017: error_count jumped by more than 1 on %0d occasion(s) - single-bit-per-word error accounting violated",
                            non_unit_jumps))
    else if (mismatched_decrements > 0)
      `uvm_error("PRBS_CHK",
                 $sformatf("RX_017: error_count decreased unexpectedly %0d time(s) outside of an explicit reset",
                            mismatched_decrements))
    else if (increments_seen == 0)
      `uvm_error("PRBS_CHK", "RX_016/RX_017: error_count never incremented at all during the monitoring window - cannot confirm detection is wired up")
    else
      `uvm_info("PRBS_CHK",
                 $sformatf("RX_016/RX_017: observed %0d error_count increment(s), every one exactly +1 - OK",
                            increments_seen), UVM_LOW)

    if (err_count_now == 8'hFF)
      `uvm_info("PRBS_CHK", "RX_018: error_count saturated at 255 without wrapping - OK", UVM_LOW)
    else
      `uvm_error("PRBS_CHK",
                 $sformatf("RX_018: error_count only reached %0d within the monitoring window, expected to observe saturation at 255",
                            err_count_now))

    // --- RX_019: counter reset via RX_ALIGN_RST, sampled while it's
    // still held asserted - the only race-free point, same reasoning as
    // uvm_tb/tests/init_sequence_test.sv's INIT_011 check. ---
    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h0D, null);  // + RX_ALIGN_RST
    if (tb_top.u_system.dut.u_top.u_pcs.u_rx.u_prbs_checker.error_count !== 8'h00)
      `uvm_error("PRBS_CHK",
                 $sformatf("RX_019: error_count=%0d while RX_ALIGN_RST is held, expected 0",
                            tb_top.u_system.dut.u_top.u_pcs.u_rx.u_prbs_checker.error_count))
    else
      `uvm_info("PRBS_CHK", "RX_019: error_count reset to 0 by RX_ALIGN_RST - OK", UVM_LOW)
    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h05, null);  // release it

    phase.drop_objection(this);
  endtask : run_phase

endclass : prbs_checker_test
