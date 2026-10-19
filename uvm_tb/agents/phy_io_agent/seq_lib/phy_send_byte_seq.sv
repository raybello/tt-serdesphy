// Sends one 8-bit byte as a single DDR transaction, matching
// serdesphy_word_assembler's DDR protocol (docs/spec.md §6.2):
// low nibble at posedge, high nibble at negedge, one tx_valid cycle.
// The assembler is always ready (tx_word_ready=1); no inter-byte gap needed.
// Set .byte_val before calling start().

class phy_send_byte_seq extends uvm_sequence #(phy_io_tr);

  `uvm_object_utils(phy_send_byte_seq)

  rand bit [7:0] byte_val;

  function new(string name = "phy_send_byte_seq");
    super.new(name);
  endfunction

  task body();
    phy_io_tr item;

    item = phy_io_tr::type_id::create("byte");
    start_item(item);
    item.kind      = PHY_IO_SEND_BYTE;
    item.byte_data = byte_val;
    finish_item(item);

    $display("[%0t] DEBUG seq: sent byte 0x%0h", $realtime, byte_val);
  endtask : body

endclass : phy_send_byte_seq
