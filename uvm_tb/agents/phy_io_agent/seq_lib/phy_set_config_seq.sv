// Sets LPBK_EN/TEST_MODE. Set .lpbk_en/.test_mode before calling
// start(); defaults match phy_io_driver's own power-up defaults
// (loopback enabled, test mode off).

class phy_set_config_seq extends uvm_sequence #(phy_io_tr);

  `uvm_object_utils(phy_set_config_seq)

  rand bit lpbk_en   = 1'b1;
  rand bit test_mode = 1'b0;

  function new(string name = "phy_set_config_seq");
    super.new(name);
  endfunction

  task body();
    phy_io_tr item = phy_io_tr::type_id::create("item");
    start_item(item);
    item.kind      = PHY_IO_SET_CONFIG;
    item.lpbk_en   = lpbk_en;
    item.test_mode = test_mode;
    finish_item(item);
  endtask : body

endclass : phy_set_config_seq
