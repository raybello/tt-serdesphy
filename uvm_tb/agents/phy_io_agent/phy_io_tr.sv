// Transactions for phy_io_agent: driving the 4-bit TX DDR interface
// (docs/spec.md section 6.2: one SEND_BYTE per 8-bit word — low nibble at
// posedge, high nibble at negedge, one tx_valid cycle) and LPBK_EN/TEST_MODE,
// plus the RX nibble observations phy_io_monitor broadcasts on its analysis
// port (two PHY_IO_RX_NIBBLE per word: low at posedge, high at negedge).

typedef enum {
  PHY_IO_SEND_BYTE,   // driver: one DDR cycle — low nibble at posedge, high at negedge
  PHY_IO_SET_CONFIG,  // driver: set lpbk_en/test_mode
  PHY_IO_RX_NIBBLE    // monitor: nibble from rx_data (emitted twice per rx_valid: rise then fall)
} phy_io_kind_e;

class phy_io_tr extends uvm_sequence_item;

  rand phy_io_kind_e kind;

  rand bit [7:0] byte_data;   // SEND_BYTE: {high_nibble[7:4], low_nibble[3:0]}
  rand bit [3:0] nibble;      // RX_NIBBLE
  rand bit       lpbk_en;     // SET_CONFIG
  rand bit       test_mode;   // SET_CONFIG

  `uvm_object_utils_begin(phy_io_tr)
    `uvm_field_enum(phy_io_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(byte_data, UVM_ALL_ON)
    `uvm_field_int(nibble, UVM_ALL_ON)
    `uvm_field_int(lpbk_en, UVM_ALL_ON)
    `uvm_field_int(test_mode, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "phy_io_tr");
    super.new(name);
  endfunction

endclass : phy_io_tr
