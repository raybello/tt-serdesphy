// PLL lock/unlock and VCO trim register behavior.
//
// This test now releases PLL_RST explicitly (csr_init_vseq leaves it asserted
// so software can program the starting VCO trim first), waits for the
// closed-loop calibration to finish, then verifies the measured 240 MHz output
// -- not just the PLL_LOCK bit. Reset is checked to clear both PLL_LOCK and
// cal_done, and a second enable must re-calibrate/re-lock.

class pll_lock_test extends uvm_test;

  `uvm_component_utils(pll_lock_test)

  serdesphy_env      env;
  virtual system_if  vif;
  bit                last_got;
  bit                last_cal_got;

  function new(string name = "pll_lock_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "pll_lock_test: virtual interface not set via uvm_config_db")
  endfunction

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

  task automatic wait_cal_done(input realtime timeout_ns);
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
  endtask : wait_cal_done

  task run_phase(uvm_phase phase);
    system_init_vseq init_seq;
    realtime          t0;
    realtime          t_start;

    phase.raise_objection(this);

    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // Release PLL reset and timestamp the actual internal reset release (the
    // I2C transaction itself takes ~100 us and is not PLL lock time).
    fork
      begin
        env.regmodel.set_pll_reset(1'b0, null);
      end
      begin
        wait (vif.pll_cal_active == 1'b1);
        t_start = $realtime;
      end
    join

    wait_cal_done(500_000);
    if (!last_cal_got)
      `uvm_error("PLL_LOCK", "cal_done did not assert after PLL_RST release")

    wait_pll_lock(50_000, 1'b1);
    if (!last_got) begin
      `uvm_error("PLL_LOCK", "CLK_004/006: PLL_LOCK did not assert")
    end else if (($realtime - t_start) > 10_000) begin
      `uvm_error("PLL_LOCK", $sformatf("CLK_004: PLL_LOCK took %0.3fus, expected <=10us",
                                        ($realtime - t_start) / 1000.0))
    end else begin
      `uvm_info("PLL_LOCK",
                $sformatf("CLK_004/006: PLL_LOCK after %0.3fus, final trim=%0d, ctrl=%0d",
                          ($realtime - t_start) / 1000.0, vif.pll_vco_trim, vif.pll_vco_control),
                UVM_LOW)
    end

    #(2us);
    if (vif.pll_freq_mhz < 235.0 || vif.pll_freq_mhz > 245.0)
      `uvm_error("PLL_LOCK",
                 $sformatf("CLK_005: measured output %0.3f MHz outside 235-245 MHz",
                           vif.pll_freq_mhz))
    else
      `uvm_info("PLL_LOCK",
                $sformatf("CLK_005: measured output %0.3f MHz - OK", vif.pll_freq_mhz),
                UVM_LOW)

    // CLK_007: PLL_RST must clear both lock and calibration.
    env.regmodel.set_pll_reset(1'b1, null);
    wait_pll_lock(30_000, 1'b0);
    if (!last_got)
      `uvm_error("PLL_LOCK", "CLK_007: PLL_LOCK did not de-assert after PLL_RST=1")
    if (vif.pll_cal_done)
      `uvm_error("PLL_LOCK", "cal_done was not cleared by PLL_RST=1")

    // Re-lock after releasing reset, confirming calibration can cycle.
    t0 = $realtime;
    env.regmodel.set_pll_reset(1'b0, null);
    wait_cal_done(500_000);
    if (!last_cal_got)
      `uvm_error("PLL_LOCK", "cal_done did not re-assert after a second PLL_RST release")
    wait_pll_lock(50_000, 1'b1);
    if (!last_got)
      `uvm_error("PLL_LOCK", "PLL_LOCK did not re-assert after releasing PLL_RST a second time")
    else
      `uvm_info("PLL_LOCK",
                $sformatf("PLL_LOCK re-locked after %0.3fus - OK", ($realtime - t0) / 1000.0),
                UVM_LOW)

    phase.drop_objection(this);
  endtask : run_phase

endclass : pll_lock_test
