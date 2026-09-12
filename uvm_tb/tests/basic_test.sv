// Default test (see run.py DEFAULT_TEST): brings the system up
// (cold reset + CSR init) and lets it idle.

class basic_test extends uvm_test;

  `uvm_component_utils(basic_test)

  serdesphy_env env;

  function new(string name = "basic_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = serdesphy_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    basic_test_vseq seq;

    phase.raise_objection(this);

    seq     = basic_test_vseq::type_id::create("seq");
    seq.cfg = clk_reset_base_cfg::type_id::create("cfg");
    seq.start(env.vseqr);

    phase.drop_objection(this);
  endtask : run_phase

endclass : basic_test
