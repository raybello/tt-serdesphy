// Passively samples system_if.clk_ref_24m / dut_rst_n and broadcasts
// measured clk_reset_tr "observations" on its analysis port:
//   - kind == CLK_RESET_START_CLK: one sample per clk period, with
//     clk_period_ps/duty_cycle_pct set to the *measured* values.
//   - kind == CLK_RESET_DEASSERT_RST: one sample per reset pulse,
//     with rst_assert_cycles set to the number of clk_ref_24m edges
//     reset was held for.
// clk_reset_cg subscribes to this port to build coverage.

class clk_reset_monitor extends uvm_monitor;

  `uvm_component_utils(clk_reset_monitor)

  virtual system_if vif;
  uvm_analysis_port #(clk_reset_tr) ap;

  function new(string name = "clk_reset_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "clk_reset_monitor: virtual interface not set via uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      sample_clk();
      sample_reset();
    join
  endtask : run_phase

  task automatic sample_clk();
    realtime t_prev_rise;
    realtime t_fall;
    bit      have_prev_rise = 1'b0;
    bit      have_fall      = 1'b0;

    forever begin
      @(posedge vif.clk_ref_24m or negedge vif.clk_ref_24m);
      if (vif.clk_ref_24m) begin
        if (have_prev_rise && have_fall) begin
          realtime   period_ns = $realtime - t_prev_rise;
          realtime   high_ns   = t_fall - t_prev_rise;
          clk_reset_tr tr = clk_reset_tr::type_id::create("clk_sample");
          tr.kind              = CLK_RESET_START_CLK;
          tr.clk_period_ps     = int'(period_ns * 1000.0);
          tr.duty_cycle_pct    = (period_ns > 0) ? int'((high_ns * 100.0) / period_ns) : 0;
          ap.write(tr);
        end
        t_prev_rise    = $realtime;
        have_prev_rise = 1'b1;
      end else begin
        t_fall    = $realtime;
        have_fall = 1'b1;
      end
    end
  endtask : sample_clk

  task automatic sample_reset();
    bit          in_reset = 1'b0;
    int unsigned cycles   = 0;

    fork
      forever begin
        @(negedge vif.dut_rst_n);
        in_reset = 1'b1;
        cycles   = 0;
      end
      forever begin
        @(posedge vif.dut_rst_n);
        if (in_reset) begin
          clk_reset_tr tr = clk_reset_tr::type_id::create("rst_sample");
          tr.kind              = CLK_RESET_DEASSERT_RST;
          tr.rst_assert_cycles = cycles;
          ap.write(tr);
        end
        in_reset = 1'b0;
      end
      forever begin
        @(posedge vif.clk_ref_24m);
        if (in_reset) cycles++;
      end
    join
  endtask : sample_reset

endclass : clk_reset_monitor
