// Full system bring-up: cold_reset_vseq (clocks + reset) followed by
// csr_init_vseq (PHY/PLL/CDR enable over I2C).

class system_init_vseq extends base_vseq;

  `uvm_object_utils(system_init_vseq)

  clk_reset_base_cfg cfg;

  function new(string name = "system_init_vseq");
    super.new(name);
  endfunction

  task body();
    cold_reset_vseq reset_seq;
    csr_init_vseq   init_seq;

    reset_seq     = cold_reset_vseq::type_id::create("reset_seq");
    reset_seq.cfg = cfg;
    reset_seq.start(p_sequencer);

    init_seq = csr_init_vseq::type_id::create("init_seq");
    init_seq.start(p_sequencer);
  endtask : body

endclass : system_init_vseq
