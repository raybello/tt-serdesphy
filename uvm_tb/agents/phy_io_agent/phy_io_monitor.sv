// Passively watches system_if.rx_data/rx_valid.
// DDR output: when rx_valid is high at posedge, emits two PHY_IO_RX_NIBBLE
// transactions per word — low nibble (word[3:0]) captured at posedge, then
// high nibble (word[7:4]) captured at the following negedge.
// (docs/spec.md §7.5: disassembler drives word[3:0] when clk=1, word[7:4] when clk=0)

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
    bit valid_rise;
    forever begin
      @(posedge vif.clk_ref_24m);
      valid_rise = vif.rx_valid;
      if (valid_rise) begin
        phy_io_tr tr_lo = phy_io_tr::type_id::create("rx_lo");
        tr_lo.kind   = PHY_IO_RX_NIBBLE;
        tr_lo.nibble = vif.rx_data;  // low nibble: disassembler drives word[3:0] at clk=1
        ap.write(tr_lo);
        `uvm_info("PHY_IO_MON", $sformatf("rx lo=0x%0h", tr_lo.nibble), UVM_HIGH)
      end
      @(negedge vif.clk_ref_24m);
      if (valid_rise) begin
        phy_io_tr tr_hi = phy_io_tr::type_id::create("rx_hi");
        tr_hi.kind   = PHY_IO_RX_NIBBLE;
        tr_hi.nibble = vif.rx_data;  // high nibble: disassembler drives word[7:4] at clk=0
        ap.write(tr_hi);
        `uvm_info("PHY_IO_MON", $sformatf("rx hi=0x%0h", tr_hi.nibble), UVM_HIGH)
      end
    end
  endtask : run_phase

endclass : phy_io_monitor
