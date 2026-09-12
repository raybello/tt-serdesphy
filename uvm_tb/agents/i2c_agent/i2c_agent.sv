class i2c_agent extends uvm_agent;

  `uvm_component_utils(i2c_agent)

  config_base   cfg;
  i2c_driver    driver;
  i2c_sequencer sequencer;
  i2c_monitor   monitor;

  function new(string name = "i2c_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(config_base)::get(this, "", "cfg", cfg))
      cfg = config_base::type_id::create("cfg");

    monitor = i2c_monitor::type_id::create("monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      driver    = i2c_driver::type_id::create("driver", this);
      sequencer = i2c_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : i2c_agent
