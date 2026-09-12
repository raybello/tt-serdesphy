class clk_reset_agent extends uvm_agent;

  `uvm_component_utils(clk_reset_agent)

  clk_reset_base_cfg  cfg;
  clk_reset_driver    driver;
  clk_reset_sequencer sequencer;
  clk_reset_monitor   monitor;

  function new(string name = "clk_reset_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(clk_reset_base_cfg)::get(this, "", "cfg", cfg))
      cfg = clk_reset_base_cfg::type_id::create("cfg");

    monitor = clk_reset_monitor::type_id::create("monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      driver    = clk_reset_driver::type_id::create("driver", this);
      sequencer = clk_reset_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : clk_reset_agent
