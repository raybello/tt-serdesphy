// PLL calibration test - closed-loop VCO trim search from every starting point.
//
// The DUT's pll_ctrl performs a closed-loop binary search: after each trim
// change it waits for the analog loop to settle, then uses the loop-filter
// control voltage to decide whether the VCO is too slow or too fast. This test
// sweeps every possible initial CSR trim (0..15), waits for cal_done, and
// checks the *internal* final trim plus the measured 240 MHz output.
//
// Unlike the earlier version, this does not read back CSR vco_trim (that is the
// starting guess, not the calibrated result) and does not accept a lock bit
// without checking the frequency.

class pll_calibration_test extends uvm_test;

  `uvm_component_utils(pll_calibration_test)

  serdesphy_env      env;
  virtual system_if  vif;
  pll_cfg            cfg;
  bit                last_cal_got;

  function new(string name = "pll_calibration_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
    cfg = pll_cfg::type_id::create("cfg");
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "pll_calibration_test: virtual interface not set")
  endfunction

  task automatic wait_cal_done(input realtime timeout_ns);
    realtime t0;
    t0 = $realtime;
    last_cal_got = 1'b0;
    fork : cal_wait_blk
      begin
        wait (vif.pll_cal_done == 1'b1);
        last_cal_got = 1'b1;
      end
      begin
        #(timeout_ns * 1ns);
      end
    join_any
    disable cal_wait_blk;
    if (last_cal_got)
      `uvm_info("PLL_CAL", $sformatf("  cal_done after %0.3f us", ($realtime - t0) / 1000.0), UVM_LOW)
  endtask

  function automatic void check_result(input int unsigned start_trim,
                                       input int unsigned final_trim,
                                       input real freq_mhz);
    if (freq_mhz < 235.0 || freq_mhz > 245.0)
      `uvm_error("PLL_CAL",
                 $sformatf("start=%0d final=%0d: output %0.3f MHz outside 235-245 MHz",
                           start_trim, final_trim, freq_mhz))
    else
      `uvm_info("PLL_CAL",
                $sformatf("  start=%0d -> final=%0d, freq=%0.3f MHz, ctrl=%0d",
                          start_trim, final_trim, freq_mhz, vif.pll_vco_control),
                UVM_LOW)

    if (final_trim < 6 || final_trim > 10)
      `uvm_warning("PLL_CAL",
                   $sformatf("start=%0d final trim=%0d is outside the expected [6:10]",
                             start_trim, final_trim))
  endfunction

  task run_phase(uvm_phase phase);
    system_init_vseq init_seq;
    int unsigned      start_trim;
    int unsigned      final_trim;
    real              freq_mhz;

    phase.raise_objection(this);

    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // csr_init_vseq intentionally leaves PLL_RST=1 so software can program the
    // starting trim before enabling the PLL.
    env.regmodel.set_pll_reset(1'b1, null);
    #(1us);

    for (int unsigned t = 0; t < 16; t++) begin
      start_trim = t[3:0];
      `uvm_info("PLL_CAL", $sformatf("Calibrating from initial VCO_TRIM=%0d", start_trim), UVM_LOW)

      env.regmodel.set_pll_reset(1'b1, null);
      #(1us);
      env.regmodel.write_csr("pll_config", "vco_trim", start_trim, null);
      env.regmodel.set_pll_reset(1'b0, null);

      wait_cal_done(500_000);
      if (!last_cal_got) begin
        `uvm_error("PLL_CAL", $sformatf("start=%0d: cal_done did not assert", start_trim))
        continue;
      end

      #(1us); // let the 1 us frequency monitor refresh
      final_trim = vif.pll_vco_trim;
      freq_mhz   = vif.pll_freq_mhz;

      if (!vif.pll_lock)
        `uvm_error("PLL_CAL", $sformatf("start=%0d: PLL_LOCK not set after cal_done", start_trim))

      check_result(start_trim, final_trim, freq_mhz);
    end

    // Calibration must be cleared by PLL_RST so a subsequent run can recalibrate.
    env.regmodel.set_pll_reset(1'b1, null);
    #(2us);
    if (vif.pll_cal_done)
      `uvm_error("PLL_CAL", "cal_done still set during PLL_RST")

    phase.drop_objection(this);
  endtask : run_phase

endclass : pll_calibration_test
