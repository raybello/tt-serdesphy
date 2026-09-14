class phy_io_agent extends uvm_agent;

  `uvm_component_utils(phy_io_agent)

  config_base    cfg;
  phy_io_driver    driver;
  phy_io_sequencer sequencer;
  phy_io_monitor   monitor;

  function new(string name = "phy_io_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(config_base)::get(this, "", "cfg", cfg))
      cfg = config_base::type_id::create("cfg");

    monitor = phy_io_monitor::type_id::create("monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      driver    = phy_io_driver::type_id::create("driver", this);
      sequencer = phy_io_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : phy_io_agent
