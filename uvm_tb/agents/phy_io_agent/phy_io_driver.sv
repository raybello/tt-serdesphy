// Drives system_if.tx_data/tx_valid using the DDR byte protocol:
// one SEND_BYTE item spans two half-periods — high nibble driven after
// posedge (stable when the negedge FF samples), low nibble + tx_valid
// driven after negedge (stable when the posedge FF samples).
// Matches serdesphy_word_assembler's DDR capture (docs/spec.md §6.2).
//
// Initializes lpbk_en=1/test_mode=0 (loopback enabled, no test mode) so
// tests that never touch this agent see the same default system.sv used to
// tie off statically before this agent existed.

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
        PHY_IO_SEND_BYTE: send_byte(item.byte_data);
        PHY_IO_SET_CONFIG: begin
          vif.lpbk_en   = item.lpbk_en;
          vif.test_mode = item.test_mode;
        end
        default: `uvm_fatal("PHY_IO_DRV", "Unknown phy_io_tr kind")
      endcase

      seq_item_port.item_done();
    end
  endtask : run_phase

  // DDR byte transfer — drive-after-edge convention:
  //   @posedge: drive high nibble; assembler negedge FF captures it at next negedge
  //   @negedge: drive low nibble + tx_valid; assembler posedge FF captures both at next posedge
  //   @posedge: word assembled (word_valid_reg=1); @negedge: deassert valid
  task automatic send_byte(input bit [7:0] byte_val);
    @(posedge vif.clk_ref_24m);
    vif.tx_data = byte_val[7:4];   // high nibble — stable for upcoming negedge capture

    @(negedge vif.clk_ref_24m);
    vif.tx_data  = byte_val[3:0];  // low nibble — stable for upcoming posedge capture
    vif.tx_valid = 1'b1;

    @(posedge vif.clk_ref_24m);    // assembler latches word + word_valid
    @(negedge vif.clk_ref_24m);
    vif.tx_valid = 1'b0;
    vif.tx_data  = 4'h0;
  endtask : send_byte

endclass : phy_io_driver
