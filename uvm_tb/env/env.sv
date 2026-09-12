// Virtual sequencer: gives vseq_lib sequences a single handle to
// reach every agent's sequencer.
class serdesphy_virtual_sequencer extends uvm_sequencer;

  `uvm_component_utils(serdesphy_virtual_sequencer)

  clk_reset_sequencer clk_reset_sqr;
  i2c_sequencer        i2c_sqr;

  function new(string name = "serdesphy_virtual_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : serdesphy_virtual_sequencer

// Top environment: clk_reset_agent + i2c_agent, coverage, and the RAL
// model wired to reach the DUT through i2c_agent's frontdoor.
class serdesphy_env extends uvm_env;

  `uvm_component_utils(serdesphy_env)

  clk_reset_agent             clk_reset_agt;
  i2c_agent                   i2c_agt;
  coverage                    cov;
  serdesphy_reg_block         regmodel;
  csr2i2c_adapter             reg2i2c_adapter;
  serdesphy_virtual_sequencer vseqr;

  function new(string name = "serdesphy_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    clk_reset_agt = clk_reset_agent::type_id::create("clk_reset_agt", this);
    i2c_agt       = i2c_agent::type_id::create("i2c_agt", this);
    cov           = coverage::type_id::create("cov", this);
    vseqr         = serdesphy_virtual_sequencer::type_id::create("vseqr", this);

    regmodel = serdesphy_reg_block::type_id::create("regmodel");
    regmodel.build();
    regmodel.reset();
    uvm_config_db#(serdesphy_reg_block)::set(this, "*", "regmodel", regmodel);

    reg2i2c_adapter = csr2i2c_adapter::type_id::create("reg2i2c_adapter");
  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    clk_reset_agt.monitor.ap.connect(cov.clk_reset_coverage.analysis_export);

    vseqr.clk_reset_sqr = clk_reset_agt.sequencer;
    vseqr.i2c_sqr        = i2c_agt.sequencer;

    regmodel.csr_map.set_sequencer(i2c_agt.sequencer, reg2i2c_adapter);
  endfunction : connect_phase

endclass : serdesphy_env
