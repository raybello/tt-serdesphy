// End-to-end TX -> internal analog loopback -> RX data-integrity test via
// the FIFO datapath specifically (TEST_CHECKLIST.md LB_004), complementing
// tx_rx_loopback_test.sv's PRBS-based check (LB_003). Verifies an exact,
// known byte sequence sent over the 4-bit TX nibble interface comes back
// out the 4-bit RX nibble interface intact.
//
// Primes the link with continuous FIFO traffic (the same repeating
// pattern under test, sent many times) so the CDR has real, continuous
// data to lock onto before the measurement pass - there is nothing to
// recover a clock from while TX is idle/the FIFO is empty. Never switches
// data sources mid-test (avoids the TX-disable gap that
// docs/info.md 5.2 requires when changing DATA_SELECT, which would force
// the alignment FSM to re-search cadence mid-test - a separate concern
// from the data-integrity question this test is asking).

class fifo_loopback_test extends uvm_test;

  `uvm_component_utils(fifo_loopback_test)

  serdesphy_env          env;
  virtual system_if      vif;
  uvm_tlm_analysis_fifo #(phy_io_tr) rx_fifo;

  // wait_cdr_lock()/get_rx_nibble() below write here rather than to task
  // output ports: SystemVerilog disallows writing an automatic task's
  // output port after a timing control has suspended it (IEEE 1800-2023
  // 13.2.2), which the fork/join_any + disable-fork timeout idiom does.
  bit       last_got;
  bit [3:0] last_rx_nibble;

  function new(string name = "fifo_loopback_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env     = serdesphy_env::type_id::create("env", this);
    rx_fifo = new("rx_fifo", this);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "fifo_loopback_test: virtual interface not set via uvm_config_db")
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.phy_io_agt.monitor.ap.connect(rx_fifo.analysis_export);
  endfunction

  task automatic wait_cdr_lock(input realtime timeout_ns);
    last_got = 1'b0;
    // Named fork block + `disable <name>`, not bare `disable fork`: this
    // task runs in the same process as run_phase's background streaming
    // fork (below) - a bare `disable fork` terminates ALL descendant
    // processes of the calling process, not just this block's own two
    // branches, which was silently killing that unrelated background
    // stream every time this returned.
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

  task automatic get_rx_nibble(input realtime timeout_ns);
    last_got = 1'b0;
    fork : nibble_wait_blk
      begin
        phy_io_tr item;
        rx_fifo.get(item);
        last_rx_nibble = item.nibble;
        last_got       = 1'b1;
      end
      begin
        #(timeout_ns * 1ns);
      end
    join_any
    disable nibble_wait_blk;
  endtask : get_rx_nibble

  task run_phase(uvm_phase phase);
    system_init_vseq init_seq;
    byte unsigned     test_bytes[5] = '{8'hA5, 8'h3C, 8'h7E, 8'h01, 8'hFF};
    bit [3:0]         expected_nibbles[$];
    realtime          t0;

    phase.raise_objection(this);

    init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.start(env.vseqr);

    // DATA_SELECT: TX_DATA_SEL=1 (FIFO), RX_DATA_SEL=0 (FIFO) - set once,
    // never switched mid-test.
    env.regmodel.write_reg_by_addr(system_pkg::REG_DATA_SELECT, 8'h01, null);
    env.regmodel.write_reg_by_addr(system_pkg::REG_RX_CONFIG, 8'h03, null);   // RX_EN=1, RX_FIFO_EN=1
    env.regmodel.write_reg_by_addr(system_pkg::REG_TX_CONFIG, 8'h03, null);   // TX_EN=1, TX_FIFO_EN=1

    foreach (test_bytes[i]) begin
      expected_nibbles.push_back(test_bytes[i][3:0]);
      expected_nibbles.push_back(test_bytes[i][7:4]);
    end

    // Keep streaming the repeating pattern continuously in the background
    // for the rest of the test (well past both CDR_LOCK acquisition and
    // nibble collection below) - TX_FIFO is only 8 words deep, so most of
    // this priming traffic overflows and is discarded once it's full;
    // that's fine, priming only needs to keep the line busy.
    fork
      begin
        for (int unsigned rep = 0; rep < 400; rep++)
          foreach (test_bytes[i]) begin
            phy_send_byte_seq seq = phy_send_byte_seq::type_id::create($sformatf("stream_%0d_%0d", rep, i));
            seq.byte_val = test_bytes[i];
            seq.start(env.vseqr.phy_io_sqr);
          end
      end
    join_none

    t0 = $realtime;
    wait_cdr_lock(600_000);
    if (!last_got) begin
      `uvm_error("FIFO_LB", "LB_004: CDR_LOCK did not assert within 600us of FIFO loopback traffic")
    end else begin
      `uvm_info("FIFO_LB",
                 $sformatf("LB_004: CDR_LOCK asserted after %0.3fus", ($realtime - t0) / 1000.0), UVM_LOW)

      // Collect a generous window of nibbles (the stream above is still
      // running) and check that some rotation of the repeating pattern
      // appears as a contiguous run somewhere in it - not necessarily at
      // position 0, since the pipeline can have a few nibbles already in
      // flight ahead of any specific point this test starts looking.
      begin
        bit [3:0]    collected[$];
        int unsigned window = expected_nibbles.size() * 4;
        int unsigned period = expected_nibbles.size();
        bit          found  = 1'b0;

        for (int unsigned i = 0; i < window && !found; i++) begin
          get_rx_nibble(50_000);
          if (!last_got) begin
            `uvm_error("FIFO_LB", $sformatf("LB_004: Timed out waiting for RX nibble %0d/%0d", i + 1, window))
            break;
          end
          collected.push_back(last_rx_nibble);

          if (collected.size() >= period) begin
            int unsigned base = collected.size() - period;
            for (int unsigned rot = 0; rot < period && !found; rot++) begin
              bit match = 1'b1;
              for (int unsigned j = 0; j < period; j++)
                if (collected[base + j] !== expected_nibbles[(j + rot) % period]) match = 1'b0;
              if (match) found = 1'b1;
            end
          end
        end

        if (found)
          `uvm_info("FIFO_LB", "LB_004: repeating FIFO test pattern found intact in RX stream - data integrity OK", UVM_LOW)
        else
          `uvm_error("FIFO_LB",
                     $sformatf("LB_004: test pattern not found in %0d collected RX nibble(s): %p",
                                collected.size(), collected))
      end
    end

    phase.drop_objection(this);
  endtask : run_phase

endclass : fifo_loopback_test
