// Top-level coverage collector: instantiates one subscriber per
// agent. env.sv connects each agent monitor's analysis port to the
// matching subscriber here.

class coverage extends uvm_component;

  `uvm_component_utils(coverage)

  clk_reset_cg clk_reset_coverage;

  function new(string name = "coverage", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    clk_reset_coverage = clk_reset_cg::type_id::create("clk_reset_coverage", this);
  endfunction

endclass : coverage
