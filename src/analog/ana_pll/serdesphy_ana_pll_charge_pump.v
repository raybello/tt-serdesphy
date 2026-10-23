/*
 * SerDes PHY PLL Charge Pump
 *
 * Behavioral, simulation-only model of a tri-state (UP/DOWN) charge pump.
 * The output is a signed pump value, not a single-bit "charge" flag:
 *   charge_out == 0  -> high-Z: the loop filter must HOLD its state
 *   charge_out  > 0  -> UP current
 *   charge_out  < 0  -> DOWN current
 *
 * The magnitude is (1 << cp_current), mirroring the datasheet's binary-weighted
 * 10/20/40/80 uA current selection. The loop filter is clocked by the VCO in
 * simulation, so the PFD's UP/DN pulse widths are integrated at VCO resolution;
 * this is what gives the loop its phase-error magnitude rather than a bang-bang
 * sign-only response.
 *
 * In silicon this whole block is replaced by the real charge pump; synthesis
 * sees a constant zero (the PLL is a hard macro).
 */

`default_nettype none
`timescale 1ns / 1ps

module serdesphy_ana_pll_charge_pump (
    input  wire       clk,             // Unused in the behavioral model
    input  wire       rst_n,
    input  wire       enable,

    input  wire [1:0] cp_current,      // 10/20/40/80 uA select

    input  wire       up_pulse,        // UP pulse from phase/frequency detector
    input  wire       down_pulse,      // DOWN pulse from phase/frequency detector

    output reg signed [4:0] charge_out // Signed tri-state pump value
);

    integer pump_gain;

    always @(*) begin
        pump_gain = 1 << cp_current;
        charge_out = 5'sd0;
        if (enable) begin
            if (up_pulse)   charge_out = charge_out + pump_gain;
            if (down_pulse) charge_out = charge_out - pump_gain;
        end
    end

    wire _unused = &{clk, rst_n};

endmodule

`default_nettype wire
