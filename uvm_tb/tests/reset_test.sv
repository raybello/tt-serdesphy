// Exercises cold_reset_vseq under both the nominal and stress
// (clk_reset_full_cfg) configurations; reset_checker/clk_checker
// (bound onto system_if) do the actual pass/fail checking.

class reset_test extends uvm_test;

  `uvm_component_utils(reset_test)

  serdesphy_env env;

  function new(string name = "reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    cold_reset_vseq     seq;
    clk_reset_base_cfg  cfg;
    clk_reset_full_cfg  fcfg;

    phase.raise_objection(this);

    cfg = clk_reset_base_cfg::type_id::create("cfg");
    assert (cfg.randomize());
    seq     = cold_reset_vseq::type_id::create("seq_nominal");
    seq.cfg = cfg;
    seq.start(env.vseqr);
    #2us;

    fcfg = clk_reset_full_cfg::type_id::create("fcfg");
    assert (fcfg.randomize());
    seq     = cold_reset_vseq::type_id::create("seq_stress");
    seq.cfg = fcfg;
    seq.start(env.vseqr);
    #2us;

    phase.drop_objection(this);
  endtask : run_phase

endclass : reset_test
