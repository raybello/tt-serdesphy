// Transactions for phy_io_agent: driving the 4-bit TX nibble interface
// (docs/info.md section 4.2 word assembly: two nibbles per 8-bit word,
// low nibble first) and LPBK_EN/TEST_MODE, plus the RX nibble/status
// observations phy_io_monitor broadcasts on its analysis port.

typedef enum {
  PHY_IO_SEND_NIBBLE,  // driver: pulse tx_data=nibble, tx_valid for one clk_ref_24m cycle
  PHY_IO_SET_CONFIG,   // driver: set lpbk_en/test_mode
  PHY_IO_RX_NIBBLE     // monitor: rx_valid sampled high, nibble = rx_data
} phy_io_kind_e;

class phy_io_tr extends uvm_sequence_item;

  rand phy_io_kind_e kind;

  rand bit [3:0] nibble;      // SEND_NIBBLE / RX_NIBBLE
  rand bit       lpbk_en;     // SET_CONFIG
  rand bit       test_mode;   // SET_CONFIG

  `uvm_object_utils_begin(phy_io_tr)
    `uvm_field_enum(phy_io_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(nibble, UVM_ALL_ON)
    `uvm_field_int(lpbk_en, UVM_ALL_ON)
    `uvm_field_int(test_mode, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "phy_io_tr");
    super.new(name);
  endfunction

endclass : phy_io_tr
