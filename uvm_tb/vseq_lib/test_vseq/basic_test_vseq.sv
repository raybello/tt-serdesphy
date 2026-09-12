// Top-level sequence for basic_test: bring the system up and let it
// idle for a bit so the checkers/coverage have something to observe.

class basic_test_vseq extends base_vseq;

  `uvm_object_utils(basic_test_vseq)

  clk_reset_base_cfg cfg;

  function new(string name = "basic_test_vseq");
    super.new(name);
  endfunction

  task body();
    system_init_vseq init_seq = system_init_vseq::type_id::create("init_seq");
    init_seq.cfg = cfg;
    init_seq.start(p_sequencer);

    #10us;
  endtask : body

endclass : basic_test_vseq
