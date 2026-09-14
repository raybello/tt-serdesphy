// Drives system_if.tx_data/tx_valid (one nibble per SEND_NIBBLE item,
// held for exactly one clk_ref_24m cycle - matches
// serdesphy_word_assembler's one-nibble-per-tx_valid-pulse protocol,
// docs/info.md section 4.2) and system_if.lpbk_en/test_mode (SET_CONFIG).
//
// Initializes lpbk_en=1/test_mode=0 (loopback enabled, no test mode) so
// tests that never touch this agent (basic_test, clk_test, reset_test,
// csr_rdwr_test) see the same default system.sv used to tie off
// statically before this agent existed.

class phy_io_driver extends uvm_driver #(phy_io_tr);

  `uvm_component_utils(phy_io_driver)

  virtual system_if vif;

  function new(string name = "phy_io_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "phy_io_driver: virtual interface not set via uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    phy_io_tr item;

    vif.tx_data   = 4'h0;
    vif.tx_valid  = 1'b0;
    vif.lpbk_en   = 1'b1;
    vif.test_mode = 1'b0;

    forever begin
      seq_item_port.get_next_item(item);

      case (item.kind)
        PHY_IO_SEND_NIBBLE: send_nibble(item.nibble);
        PHY_IO_SET_CONFIG: begin
          vif.lpbk_en   = item.lpbk_en;
          vif.test_mode = item.test_mode;
        end
        default: `uvm_fatal("PHY_IO_DRV", "Unknown phy_io_tr kind")
      endcase

      seq_item_port.item_done();
    end
  endtask : run_phase

  // Drives tx_data/tx_valid so exactly one clk_ref_24m rising edge sees
  // tx_valid=1 with tx_data=nibble stable around it.
  task automatic send_nibble(input bit [3:0] nibble);
    @(negedge vif.clk_ref_24m);
    vif.tx_data  = nibble;
    vif.tx_valid = 1'b1;
    @(posedge vif.clk_ref_24m);
    @(negedge vif.clk_ref_24m);
    vif.tx_valid = 1'b0;
  endtask : send_nibble

endclass : phy_io_driver
