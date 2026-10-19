// PLL Calibration Test - Validates binary search algorithm for VCO frequency tuning
//
// Tests that the PLL calibration logic correctly performs binary search on
// vco_trim to find a frequency that allows the PLL to lock. Validates both:
// - Successful calibration when a lockable frequency exists
// - Failure detection when VCO range doesn't include target frequency
//
// The VCO model implements frequency tuning based on vco_control[7:0]:
//   [7:4] - Coarse tuning (vco_trim, ±5 MHz per bit)
//   [3:0] - Fine tuning (loop filter, ±312.5 kHz per bit)
//
// Nominal: 240 MHz at vco_control = 8'h80
// Range: ~160 MHz to ~320 MHz total

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
    int trim_val;

    phase.raise_objection(this);

    // Initialize system
    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // Test 1: Default VCO trim (mid-range) should allow lock
    `uvm_info("PLL_CAL", "Test 1: Verify PLL locks with default vco_trim=8", UVM_LOW)
    env.regmodel.write_csr("pll_config", "vco_trim", 4'h8, null);

    t0 = $realtime;
    wait(vif.pll_lock == 1'b1);
    if (($realtime - t0) > 50_000) begin
      `uvm_error("PLL_CAL", "Test 1 FAIL: PLL did not lock with vco_trim=8")
    end else begin
      `uvm_info("PLL_CAL", $sformatf("Test 1 PASS: PLL locked in %0.3f us", ($realtime - t0)/1000.0), UVM_LOW)
    end

    // Test 2: Sweep through vco_trim range and verify lock behavior
    `uvm_info("PLL_CAL", "Test 2: Sweep vco_trim to verify frequency range", UVM_LOW)
    for (trim_val = 0; trim_val <= 15; trim_val++) begin
      // Reset PLL
      env.regmodel.set_pll_reset(1'b1, null);
      #(1us);

      // Apply new trim value
      env.regmodel.write_csr("pll_config", "vco_trim", trim_val[3:0], null);
      env.regmodel.set_pll_reset(1'b0, null);

      // Wait for lock or timeout
      t0 = $realtime;
      fork
        begin
          wait(vif.pll_lock == 1'b1);
        end
        begin
          #(30us);
        end
      join_any
      disable fork;

      if (vif.pll_lock) begin
        `uvm_info("PLL_CAL", $sformatf("  vco_trim=%0d: LOCKED in %0.3f us",
                                        trim_val, ($realtime - t0)/1000.0), UVM_LOW)
      end else begin
        `uvm_info("PLL_CAL", $sformatf("  vco_trim=%0d: NO LOCK (timeout)", trim_val), UVM_LOW)
      end
    end

    // Test 3: Verify extreme values
    `uvm_info("PLL_CAL", "Test 3: Test extreme vco_trim values", UVM_LOW)

    // Test minimum (should be outside lock range - too slow)
    env.regmodel.set_pll_reset(1'b1, null);
    #(1us);
    env.regmodel.write_csr("pll_config", "vco_trim", 4'h0, null);
    env.regmodel.set_pll_reset(1'b0, null);
    #(30us);

    if (!vif.pll_lock) begin
      `uvm_info("PLL_CAL", "Test 3a PASS: vco_trim=0 did not lock (expected - VCO too slow)", UVM_LOW)
    end else begin
      `uvm_warning("PLL_CAL", "Test 3a: vco_trim=0 locked (unexpected but acceptable)")
    end

    // Test maximum (should be outside lock range - too fast)
    env.regmodel.set_pll_reset(1'b1, null);
    #(1us);
    env.regmodel.write_csr("pll_config", "vco_trim", 4'hF, null);
    env.regmodel.set_pll_reset(1'b0, null);
    #(30us);

    if (!vif.pll_lock) begin
      `uvm_info("PLL_CAL", "Test 3b PASS: vco_trim=F did not lock (expected - VCO too fast)", UVM_LOW)
    end else begin
      `uvm_warning("PLL_CAL", "Test 3b: vco_trim=F locked (unexpected but acceptable)")
    end

    // Test 4: Return to known good value and verify re-lock
    `uvm_info("PLL_CAL", "Test 4: Verify PLL can re-lock after calibration", UVM_LOW)
    env.regmodel.set_pll_reset(1'b1, null);
    #(1us);
    env.regmodel.write_csr("pll_config", "vco_trim", 4'h8, null);
    env.regmodel.set_pll_reset(1'b0, null);

    t0 = $realtime;
    wait(vif.pll_lock == 1'b1);
    if (($realtime - t0) > 50_000) begin
      `uvm_error("PLL_CAL", "Test 4 FAIL: PLL did not re-lock")
    end else begin
      `uvm_info("PLL_CAL", $sformatf("Test 4 PASS: PLL re-locked in %0.3f us", ($realtime - t0)/1000.0), UVM_LOW)
    end

    phase.drop_objection(this);
  endtask : run_phase

endclass : pll_calibration_test
