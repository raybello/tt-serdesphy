/*
 * SerDes PHY PLL VCO
 * Synthesis: constant-0 placeholder (replaced by analog ring oscillator in silicon).
 * Simulation: continuous behavioral oscillator with frequency control modeling.
 *
 * Frequency model (kept linear; see docs/info.md section 5.5):
 *   - vco_control: 8-bit fine control from the loop filter (0-255, nominal 128)
 *   - vco_trim:    4-bit coarse control (0-15, nominal 8)
 *   - Fine step:   312.5 kHz per vco_control step (+/-40 MHz total)
 *   - Coarse step: 5 MHz per vco_trim step (+/-40 MHz total)
 *   - Nominal:     240 MHz at vco_control=128, vco_trim=8
 *   - Range:       ~160 MHz to ~315 MHz (trim 0/control 0 .. trim 15/control 255)
 *
 * The oscillator is a continuous phase accumulator: the current control word is
 * re-sampled every half period, so a control change never restarts the phase.
 * This is simulation-only; synthesis sees a constant 0.
 */

`default_nettype none
`timescale 1ns / 1ps

module serdesphy_ana_pll_vco (
    input  wire       rst_n,
    input  wire       enable,
    input  wire [7:0] vco_control,     // From loop filter (0-255, centered at 128)
    input  wire [3:0] vco_trim,        // Static coarse offset (0-15, nominal=8)
    output reg        vco_out,
    output wire       vco_ready
);

`ifndef SYNTHESIS
    real half_period_ns;

    function real calc_frequency_mhz;
        input [7:0] ctrl;
        input [3:0] trim;
        integer ctrl_int;
        integer trim_int;
        begin
            ctrl_int = ctrl;
            trim_int = trim;
            calc_frequency_mhz = 240.0
                               + (trim_int - 8) * 5.0
                               + (ctrl_int - 128) * 0.3125;
        end
    endfunction

    initial vco_out = 1'b0;

    always begin
        if (!rst_n || !enable) begin
            vco_out = 1'b0;
            @(posedge enable or posedge rst_n);
        end else begin
            half_period_ns = 500.0 / calc_frequency_mhz(vco_control, vco_trim);
            if (half_period_ns < 0.1) half_period_ns = 0.1;
            #(half_period_ns * 1ns);
            if (rst_n && enable) vco_out = ~vco_out;
        end
    end

`else
    // Synthesis placeholder
    assign vco_out = 1'b0;
`endif

    assign vco_ready = rst_n & enable;

endmodule

`default_nettype wire
