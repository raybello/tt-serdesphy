// Starts clk_ref_24m toggling based on cfg (period/duty/jitter). Set
// .cfg before calling start() to drive from clk_reset_base_cfg or
// clk_reset_full_cfg; falls back to a nominal 24 MHz/50%/no-jitter
// clock otherwise.

class clk_reset_start_clk_seq extends uvm_sequence #(clk_reset_tr);

  `uvm_object_utils(clk_reset_start_clk_seq)

  clk_reset_base_cfg cfg;

  function new(string name = "clk_reset_start_clk_seq");
    super.new(name);
  endfunction

  task body();
    clk_reset_tr item = clk_reset_tr::type_id::create("item");
    start_item(item);
    item.kind           = CLK_RESET_START_CLK;
    item.clk_period_ps  = (cfg != null) ? cfg.clk_period_ps : 41667;
    item.duty_cycle_pct = (cfg != null) ? cfg.duty_cycle_pct : 50;
    item.jitter_ps      = (cfg != null) ? cfg.jitter_ps : 0;
    finish_item(item);
  endtask : body

endclass : clk_reset_start_clk_seq
