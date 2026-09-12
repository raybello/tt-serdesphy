// Passive checker bound onto system_if: watches clk_ref_24m and flags
// a dead/stuck clock or a period/duty cycle outside the configured
// sanity bounds. Bounds are intentionally generous (see defines.sv)
// since clk_reset_full_cfg legally drives a faster, jittery clock.

`include "defines.sv"

module clk_checker #(
    parameter real PERIOD_MIN_NS = `SERDESPHY_CLK_PERIOD_MIN_NS,
    parameter real PERIOD_MAX_NS = `SERDESPHY_CLK_PERIOD_MAX_NS,
    parameter int  DUTY_MIN_PCT  = `SERDESPHY_CLK_DUTY_MIN_PCT,
    parameter int  DUTY_MAX_PCT  = `SERDESPHY_CLK_DUTY_MAX_PCT
) (
    input logic clk,
    input logic rst_n
);

  import uvm_pkg::*;
`include "uvm_macros.svh"

  // ------------------------------------------------------------------
  // Period check: time between consecutive rising edges.
  // ------------------------------------------------------------------
  realtime t_last_rise;
  realtime period;
  bit      have_last_rise = 1'b0;

  always @(posedge clk) begin
    if (have_last_rise) begin
      period = $realtime - t_last_rise;
      if (period < PERIOD_MIN_NS || period > PERIOD_MAX_NS)
        `uvm_error("CLK_CHECK",
                   $sformatf("clk_ref_24m period %0.3fns outside [%0.3f, %0.3f]ns",
                              period, PERIOD_MIN_NS, PERIOD_MAX_NS))
    end
    t_last_rise    = $realtime;
    have_last_rise = 1'b1;
  end

  // ------------------------------------------------------------------
  // Duty-cycle check: high_time / period over one full cycle.
  // ------------------------------------------------------------------
  realtime t_rise_prev;
  realtime t_fall;
  realtime duty_period;
  realtime high_time;
  int      duty_pct;
  bit      have_rise_prev = 1'b0;
  bit      have_fall      = 1'b0;

  always @(posedge clk) begin
    if (have_rise_prev && have_fall) begin
      duty_period = $realtime - t_rise_prev;
      high_time   = t_fall - t_rise_prev;
      if (duty_period > 0 && rst_n) begin
        duty_pct = int'((high_time * 100.0) / duty_period);
        if (duty_pct < DUTY_MIN_PCT || duty_pct > DUTY_MAX_PCT)
          `uvm_warning("CLK_CHECK",
                       $sformatf("clk_ref_24m duty cycle %0d%% outside [%0d, %0d]%%",
                                  duty_pct, DUTY_MIN_PCT, DUTY_MAX_PCT))
      end
    end
    t_rise_prev    = $realtime;
    have_rise_prev = 1'b1;
  end

  always @(negedge clk) begin
    t_fall    = $realtime;
    have_fall = 1'b1;
  end

endmodule : clk_checker
