// Exercises clk_reset_full_cfg (faster clock, jitter) plus a
// stop/restart cycle; clk_checker (bound onto system_if) verifies
// the clock never goes dead or out of its sanity bounds.

class clk_test extends uvm_test;

  `uvm_component_utils(clk_test)

  serdesphy_env env;

  function new(string name = "clk_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    cold_reset_vseq         reset_seq;
    clk_reset_stop_clk_seq  stop_seq;
    clk_reset_start_clk_seq restart_seq;
    clk_reset_full_cfg      cfg;

    phase.raise_objection(this);

    cfg = clk_reset_full_cfg::type_id::create("cfg");
    assert (cfg.randomize());

    reset_seq     = cold_reset_vseq::type_id::create("reset_seq");
    reset_seq.cfg = cfg;
    reset_seq.start(env.vseqr);

    #5us;

    stop_seq = clk_reset_stop_clk_seq::type_id::create("stop_seq");
    stop_seq.start(env.vseqr.clk_reset_sqr);

    #1us;

    restart_seq     = clk_reset_start_clk_seq::type_id::create("restart_seq");
    restart_seq.cfg = cfg;
    restart_seq.start(env.vseqr.clk_reset_sqr);

    #5us;

    phase.drop_objection(this);
  endtask : run_phase

endclass : clk_test
