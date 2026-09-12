// Functional coverage for clk_reset_agent: subscribes to
// clk_reset_monitor.ap and samples measured clock period/duty cycle
// and reset hold time.

class clk_reset_cg extends uvm_subscriber #(clk_reset_tr);

  `uvm_component_utils(clk_reset_cg)

  protected clk_reset_tr tr;

  covergroup cg;
    option.per_instance = 1;

    cp_kind: coverpoint tr.kind {
      bins start_clk    = {CLK_RESET_START_CLK};
      bins deassert_rst = {CLK_RESET_DEASSERT_RST};
    }

    cp_period: coverpoint tr.clk_period_ps iff (tr.kind == CLK_RESET_START_CLK) {
      bins nominal = {[35_000 : 45_000]};
      bins fast    = {[8_000  : 20_000]};
      bins other   = default;
    }

    cp_duty: coverpoint tr.duty_cycle_pct iff (tr.kind == CLK_RESET_START_CLK) {
      bins low     = {[0  : 44]};
      bins nominal = {[45 : 55]};
      bins high    = {[56 : 100]};
    }

    cp_rst_cycles: coverpoint tr.rst_assert_cycles iff (tr.kind == CLK_RESET_DEASSERT_RST) {
      bins short = {[10 : 20]};
      bins long  = {[21 : 40]};
      bins other = default;
    }

  endgroup : cg

  function new(string name = "clk_reset_cg", uvm_component parent = null);
    super.new(name, parent);
    cg = new();
  endfunction

  function void write(clk_reset_tr t);
    tr = t;
    cg.sample();
  endfunction : write

endclass : clk_reset_cg
