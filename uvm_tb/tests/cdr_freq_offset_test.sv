// CDR Frequency Offset Acquisition Test
//
// Tests limitation L1 resolution: CDR VCO can acquire and track a TX signal
// with frequency offset up to ±2000 ppm (spec requirement).
//
// This test validates:
// 1. CDR can acquire lock when RX VCO starts at a different frequency than TX PLL
// 2. CDR tracking bandwidth is sufficient to maintain lock
// 3. PRBS data integrity is maintained even with frequency offset
//
// Run with: +CDR_FREQ_OFFSET_PPM=<value> to set the initial frequency offset
// Example: +CDR_FREQ_OFFSET_PPM=2000.0 tests maximum positive offset
//          +CDR_FREQ_OFFSET_PPM=-2000.0 tests maximum negative offset
//
// Without the plusarg, defaults to 0 ppm (backward compatibility check).

class cdr_freq_offset_test extends uvm_test;

  `uvm_component_utils(cdr_freq_offset_test)

  serdesphy_env     env;
  virtual system_if vif;

  // Test parameters
  real freq_offset_ppm = 0.0;
  bit last_got;

  function new(string name = "cdr_freq_offset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "cdr_freq_offset_test: virtual interface not set via uvm_config_db")

    // Read frequency offset from plusarg (set in project.v)
    if ($value$plusargs("CDR_FREQ_OFFSET_PPM=%f", freq_offset_ppm)) begin
      `uvm_info("CDR_FREQ",
                $sformatf("CDR frequency offset configured: %0.1f ppm", freq_offset_ppm),
                UVM_MEDIUM)
    end else begin
      `uvm_info("CDR_FREQ",
                "No frequency offset specified - testing nominal (0 ppm) case",
                UVM_MEDIUM)
    end
  endfunction

  // Wait for PLL lock with timeout
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

  // Wait for CDR lock with timeout
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

  // Watch for PRBS errors during a monitoring window
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
    realtime          cdr_lock_time_us;

    phase.raise_objection(this);

    `uvm_info("CDR_FREQ",
              "========================================",
              UVM_MEDIUM)
    `uvm_info("CDR_FREQ",
              " CDR Frequency Offset Acquisition Test",
              UVM_MEDIUM)
    `uvm_info("CDR_FREQ",
              $sformatf(" Frequency Offset: %0.1f ppm", freq_offset_ppm),
              UVM_MEDIUM)
    `uvm_info("CDR_FREQ",
              "========================================",
              UVM_MEDIUM)

    // Initialize system
    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // Wait for PLL lock (TX clock reference)
    `uvm_info("CDR_FREQ", "Waiting for PLL lock (TX reference)...", UVM_MEDIUM)
    t0 = $realtime;
    wait_pll_lock(50_000);
    if (!last_got) begin
      `uvm_error("CDR_FREQ", "PLL_LOCK did not assert - TX clock not ready")
      phase.drop_objection(this);
      return;
    end
    `uvm_info("CDR_FREQ",
              $sformatf("PLL locked after %0.3f us", ($realtime - t0) / 1000.0),
              UVM_MEDIUM)

    // Enable TX with PRBS pattern
    `uvm_info("CDR_FREQ", "Enabling TX with PRBS-7 pattern...", UVM_MEDIUM)
    env.regmodel.write_reg_by_addr(system_pkg::REG_TX_CONFIG, 8'h05, null);  // TX_EN=1, TX_PRBS_EN=1

    // Enable RX with PRBS checker
    `uvm_info("CDR_FREQ", "Enabling RX with PRBS checker...", UVM_MEDIUM)
    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h05, null);  // RX_EN=1, RX_PRBS_CHK_EN=1

    // Wait for CDR lock - this is where frequency acquisition happens
    // With frequency offset, the CDR VCO starts at offset frequency and must
    // pull into alignment with the TX data rate. Timeout is generous to allow
    // for larger offsets (spec allows up to 100us typical, 600us gives margin).
    `uvm_info("CDR_FREQ",
              "Waiting for CDR lock (frequency acquisition in progress)...",
              UVM_MEDIUM)
    t0 = $realtime;
    wait_cdr_lock(600_000);

    if (!last_got) begin
      `uvm_error("CDR_FREQ",
                 $sformatf("CDR_LOCK did not assert within 600us with %0.1f ppm offset - acquisition failed",
                           freq_offset_ppm))
      phase.drop_objection(this);
      return;
    end

    cdr_lock_time_us = ($realtime - t0) / 1000.0;
    `uvm_info("CDR_FREQ",
              $sformatf("CDR locked after %0.3f us with %0.1f ppm offset - ACQUISITION SUCCESS",
                        cdr_lock_time_us, freq_offset_ppm),
              UVM_MEDIUM)

    // Clear any PRBS errors accumulated during acquisition
    `uvm_info("CDR_FREQ", "Clearing PRBS errors from acquisition phase...", UVM_MEDIUM)
    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h0D, null);  // + RX_ALIGN_RST
    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h05, null);  // release
    #(5us);

    // Monitor PRBS errors to verify data integrity with frequency offset
    // This validates that CDR tracking bandwidth is sufficient
    `uvm_info("CDR_FREQ",
              "Monitoring PRBS integrity (tracking bandwidth validation)...",
              UVM_MEDIUM)
    watch_for_prbs_err(200_000);  // 200us monitoring window

    if (last_got) begin
      `uvm_error("CDR_FREQ",
                 $sformatf("PRBS_ERR asserted with %0.1f ppm offset - tracking bandwidth insufficient",
                           freq_offset_ppm))
    end else begin
      `uvm_info("CDR_FREQ",
                $sformatf("No PRBS errors for 200us with %0.1f ppm offset - TRACKING BANDWIDTH OK",
                          freq_offset_ppm),
                UVM_MEDIUM)
    end

    `uvm_info("CDR_FREQ",
              "========================================",
              UVM_MEDIUM)
    `uvm_info("CDR_FREQ",
              " TEST SUMMARY",
              UVM_MEDIUM)
    `uvm_info("CDR_FREQ",
              $sformatf(" Frequency Offset: %0.1f ppm", freq_offset_ppm),
              UVM_MEDIUM)
    `uvm_info("CDR_FREQ",
              $sformatf(" CDR Lock Time: %0.3f us", cdr_lock_time_us),
              UVM_MEDIUM)
    `uvm_info("CDR_FREQ",
              $sformatf(" Data Integrity: %s", last_got ? "FAIL" : "PASS"),
              UVM_MEDIUM)
    `uvm_info("CDR_FREQ",
              "========================================",
              UVM_MEDIUM)

    phase.drop_objection(this);
  endtask : run_phase

endclass : cdr_freq_offset_test
