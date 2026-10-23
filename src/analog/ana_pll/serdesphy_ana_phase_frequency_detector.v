/*
 * SerDes PHY Phase-Frequency Detector
 *
 * Behavioral classical PFD: two resettable flip-flops produce UP/DN pulses
 * whose widths are the phase error. The charge pump plus VCO-clocked loop
 * filter integrate those widths, so this behaves as a real tri-state PFD
 * rather than a sign-only bang-bang detector.
 *
 * The explicit initial values matter for RTL simulators that do not
 * zero-initialize regs (Icarus): the PLL is enabled only after rst_n has
 * already gone high, so there may be no negedge rst_n to reset these regs.
 * Synthesis replaces this block with the analog PFD.
 */

`default_nettype none
`timescale 1ns / 1ps

module serdesphy_ana_phase_frequency_detector (
    input  wire       clk_ref,         // Reference clock
    input  wire       clk_feedback,    // Divided VCO feedback clock
    input  wire       rst_n,
    input  wire       enable,

    output wire       up_pulse,
    output wire       down_pulse
);

`ifndef SYNTHESIS
    reg up_ff, down_ff;
    wire reset_both = up_ff && down_ff;

    initial begin
        up_ff   = 1'b0;
        down_ff = 1'b0;
    end

    always @(posedge clk_ref or negedge rst_n or posedge reset_both) begin
        if (!rst_n) begin
            up_ff <= 1'b0;
        end else if (reset_both) begin
            up_ff <= 1'b0;
        end else if (enable) begin
            up_ff <= 1'b1;
        end
    end

    always @(posedge clk_feedback or negedge rst_n or posedge reset_both) begin
        if (!rst_n) begin
            down_ff <= 1'b0;
        end else if (reset_both) begin
            down_ff <= 1'b0;
        end else if (enable) begin
            down_ff <= 1'b1;
        end
    end

    assign up_pulse   = up_ff && enable;
    assign down_pulse = down_ff && enable;

`else
    assign up_pulse   = 1'b0;
    assign down_pulse = 1'b0;
`endif

endmodule

`default_nettype wire
