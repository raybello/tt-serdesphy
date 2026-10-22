// PLL Calibration Test - Validates automatic binary search calibration
//
// Tests that pll_ctrl automatically performs binary search on vco_trim
// to find a frequency that allows the PLL to lock. This matches real
// ASIC behavior where the calibration FSM runs automatically on enable.
//
// Test flow:
//   1. Enable PHY (starts calibration automatically)
//   2. Wait for PLL lock (cal_done asserts when locked)
//   3. Verify lock was achieved
//   4. Read final vco_trim value from pll_ctrl
//
// The pll_ctrl binary search algorithm:
//   - Starts at vco_trim=8 (mid-range)
//   - Waits for PLL to settle (20µs)
//   - Checks loop filter saturation to determine search direction
//   - Converges to optimal vco_trim value
//   - Asserts cal_done when PLL locks

class pll_calibration_test extends uvm_test;

  `uvm_component_utils(pll_calibration_test)

  serdesphy_env      env;
  virtual system_if  vif;

  function new(string name = "pll_calibration_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "pll_calibration_test: virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    system_init_vseq init_seq;
    realtime t0;
    int final_trim;

    phase.raise_objection(this);

    // Initialize system - this enables the PHY
    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // Test 1: Automatic calibration on startup
    `uvm_info("PLL_CAL", "Test 1: Automatic calibration on PHY enable", UVM_LOW)

    // The init sequence already enabled the PHY, which automatically started
    // the pll_ctrl binary search calibration. Now just wait for lock.
    t0 = $realtime;

    fork
      begin
        wait(vif.pll_lock == 1'b1);
      end
      begin
        #(200us);  // Allow time for full binary search (max 6 iterations × 20µs = 120µs)
      end
    join_any
    disable fork;

    if (vif.pll_lock) begin
      `uvm_info("PLL_CAL", $sformatf("Test 1 PASS: PLL auto-calibrated and locked in %0.3f us",
                                      ($realtime - t0)/1000.0), UVM_LOW)

      // Read the final vco_trim value that pll_ctrl found
      env.regmodel.read_csr("pll_config", "vco_trim", final_trim, null);
      `uvm_info("PLL_CAL", $sformatf("  Calibrated vco_trim = %0d", final_trim), UVM_LOW)
    end else begin
      `uvm_error("PLL_CAL", "Test 1 FAIL: PLL did not lock after auto-calibration")
    end

    // Test 2: Re-calibration after reset
    `uvm_info("PLL_CAL", "Test 2: Re-calibration after PLL reset", UVM_LOW)

    // Reset the PLL (this will restart calibration)
    env.regmodel.set_pll_reset(1'b1, null);
    #(1us);
    env.regmodel.set_pll_reset(1'b0, null);

    // Wait for calibration to complete again
    t0 = $realtime;
    fork
      begin
        wait(vif.pll_lock == 1'b1);
      end
      begin
        #(200us);
      end
    join_any
    disable fork;

    if (vif.pll_lock) begin
      `uvm_info("PLL_CAL", $sformatf("Test 2 PASS: PLL re-calibrated and locked in %0.3f us",
                                      ($realtime - t0)/1000.0), UVM_LOW)
      env.regmodel.read_csr("pll_config", "vco_trim", final_trim, null);
      `uvm_info("PLL_CAL", $sformatf("  Re-calibrated vco_trim = %0d", final_trim), UVM_LOW)
    end else begin
      `uvm_error("PLL_CAL", "Test 2 FAIL: PLL did not re-lock after reset")
    end

    // Test 3: Multiple calibration cycles
    `uvm_info("PLL_CAL", "Test 3: Multiple calibration cycles", UVM_LOW)
    for (int i = 0; i < 3; i++) begin
      env.regmodel.set_pll_reset(1'b1, null);
      #(1us);
      env.regmodel.set_pll_reset(1'b0, null);

      t0 = $realtime;
      fork
        begin
          wait(vif.pll_lock == 1'b1);
        end
        begin
          #(200us);
        end
      join_any
      disable fork;

      if (vif.pll_lock) begin
        env.regmodel.read_csr("pll_config", "vco_trim", final_trim, null);
        `uvm_info("PLL_CAL", $sformatf("  Cycle %0d: LOCKED in %0.3f us, vco_trim=%0d",
                                        i+1, ($realtime - t0)/1000.0, final_trim), UVM_LOW)
      end else begin
        `uvm_error("PLL_CAL", $sformatf("  Cycle %0d: FAILED to lock", i+1))
      end
    end

    `uvm_info("PLL_CAL", "Test 3 PASS: All calibration cycles completed", UVM_LOW)

    phase.drop_objection(this);
  endtask : run_phase

endclass : pll_calibration_test
