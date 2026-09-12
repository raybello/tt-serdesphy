// Deasserts reset after cfg.rst_assert_cycles clk_ref_24m cycles (see
// clk_reset_driver). Set .cfg before calling start() to pull the hold
// time from a specific clk_reset_base_cfg/clk_reset_full_cfg; falls
// back to the default reset-cycle count otherwise.

class clk_reset_deassert_rst_seq extends uvm_sequence #(clk_reset_tr);

  `uvm_object_utils(clk_reset_deassert_rst_seq)

  clk_reset_base_cfg cfg;

  function new(string name = "clk_reset_deassert_rst_seq");
    super.new(name);
  endfunction

  task body();
    clk_reset_tr item = clk_reset_tr::type_id::create("item");
    start_item(item);
    item.kind              = CLK_RESET_DEASSERT_RST;
    item.rst_assert_cycles = (cfg != null) ? cfg.rst_assert_cycles : `SERDESPHY_MIN_RESET_CYCLES;
    item.clk_period_ps     = (cfg != null) ? cfg.clk_period_ps : 41667;
    finish_item(item);
  endtask : body

endclass : clk_reset_deassert_rst_seq
