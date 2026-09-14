// Sends one 8-bit byte as two nibbles, low nibble first, matching
// serdesphy_word_assembler's assembly order (docs/info.md section 4.2).
// Set .byte_val before calling start().

class phy_send_byte_seq extends uvm_sequence #(phy_io_tr);

  `uvm_object_utils(phy_send_byte_seq)

  rand bit [7:0] byte_val;

  function new(string name = "phy_send_byte_seq");
    super.new(name);
  endfunction

  task body();
    phy_io_tr item;

    item = phy_io_tr::type_id::create("low_nibble");
    start_item(item);
    item.kind   = PHY_IO_SEND_NIBBLE;
    item.nibble = byte_val[3:0];
    finish_item(item);

    item = phy_io_tr::type_id::create("high_nibble");
    start_item(item);
    item.kind   = PHY_IO_SEND_NIBBLE;
    item.nibble = byte_val[7:4];
    finish_item(item);

    // serdesphy_word_assembler needs two more clk_24m cycles after the
    // second nibble (STATE_WORD_READY -> STATE_OUTPUT_WORD, neither of
    // which samples tx_valid) before it's back in STATE_WAIT_NIBBLE_0 and
    // ready for the next byte's first nibble - sending back-to-back with
    // no gap here drops that nibble on the floor and corrupts framing for
    // everything after it. This matches docs/info.md section 4.2's "4-bit
    // parallel data at 12 MHz effective rate": real hardware paces
    // nibbles, it doesn't blast them at the full 24 MHz clock rate.
    #(4 * `SERDESPHY_REF_CLK_PERIOD_NS * 1ns);
    $display("[%0t] DEBUG seq: sent byte 0x%0h", $realtime, byte_val);
  endtask : body

endclass : phy_send_byte_seq
