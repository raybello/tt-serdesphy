// Passively watches system_if.rx_data/rx_valid and broadcasts one
// PHY_IO_RX_NIBBLE transaction per clk_ref_24m cycle where rx_valid is
// high, carrying the nibble seen on rx_data that cycle.

class phy_io_monitor extends uvm_monitor;

  `uvm_component_utils(phy_io_monitor)

  virtual system_if vif;
  uvm_analysis_port #(phy_io_tr) ap;

  function new(string name = "phy_io_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "phy_io_monitor: virtual interface not set via uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk_ref_24m);
      if (vif.rx_valid) begin
        phy_io_tr tr = phy_io_tr::type_id::create("rx_nibble");
        tr.kind   = PHY_IO_RX_NIBBLE;
        tr.nibble = vif.rx_data;
        ap.write(tr);
        `uvm_info("PHY_IO_MON", $sformatf("rx nibble=0x%0h", tr.nibble), UVM_HIGH)
      end
    end
  endtask : run_phase

endclass : phy_io_monitor
