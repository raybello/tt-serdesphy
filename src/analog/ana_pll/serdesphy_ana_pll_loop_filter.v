/*
 * SerDes PHY PLL Loop Filter
 *
 * Behavioral type-II loop filter with a frequency-acquisition aid.
 *
 * The phase path integrates the signed charge-pump output on every VCO edge,
 * which preserves the PFD's UP/DN pulse widths (phase magnitude) instead of
 * collapsing them to a sign bit. A second, slower path adds a frequency-error
 * correction every FREQ_WINDOW reference cycles; that is what gives the model
 * a wide, symmetric acquisition range without making the locked loop jittery.
 *
 * Control law (Q8 fixed point on the integrator):
 *   integ += charge_in * KI_PHASE
 *   integ += freq_error * KI_FREQ        (only when |freq_error| > 1)
 *   vco_control = clamp(128 + integ/256 + KP*charge_in, 0, 255)
 *
 * Gains were tuned against the 24 MHz reference / 240 MHz VCO / 8-10 us lock
 * target with the datasheet's linear 200-275 MHz trim map.
 */

`default_nettype none
`timescale 1ns / 1ps

module serdesphy_ana_pll_loop_filter (
    input  wire             clk,             // VCO clock (phase path)
    input  wire             rst_n,
    input  wire             enable,

    input  wire signed [4:0] charge_in,      // Signed charge-pump output
    input  wire signed [9:0] freq_error,     // VCO-cycle error over one window
    input  wire              freq_valid,     // One-cycle pulse per window

    output reg  [7:0]        vco_control
);

    // Phase path: ~8 codes per VCO cycle with the default 40 uA setting
    // (charge_in is +/-4 at cp_current=2, so KI_PHASE=2 gives the effective 8).
    localparam integer KI_PHASE = 2;
    localparam integer KI_FREQ  = 410;
    localparam integer KP       = 1;

    reg signed [31:0] integ_q8;
    integer sum_q8;
    reg freq_valid_d;

    initial begin
        integ_q8     = 32'sd0;
        vco_control  = 8'd128;
        freq_valid_d = 1'b0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            integ_q8     <= 32'sd0;
            vco_control  <= 8'd128;
            freq_valid_d <= 1'b0;
        end else if (!enable) begin
            integ_q8     <= 32'sd0;
            vco_control  <= 8'd128;
            freq_valid_d <= 1'b0;
        end else begin
            freq_valid_d <= freq_valid;
            integ_q8 <= integ_q8 + charge_in * KI_PHASE;

            if (freq_valid && !freq_valid_d &&
                (freq_error > 9'sd1 || freq_error < -9'sd1))
                integ_q8 <= integ_q8 + freq_error * KI_FREQ;

            // Anti-windup: the 8-bit control can only represent 0..255, i.e.
            // +/-128 codes around centre. Clamp the integrator there.
            if (integ_q8 > 32'sd128 * 256) integ_q8 <= 32'sd128 * 256;
            if (integ_q8 < -32'sd128 * 256) integ_q8 <= -32'sd128 * 256;

            sum_q8 = 32'sd128 * 256 + integ_q8 + KP * 256 * charge_in;
            if (sum_q8 > 255 * 256)      vco_control <= 8'd255;
            else if (sum_q8 < 0)         vco_control <= 8'd0;
            else                         vco_control <= sum_q8[15:8];
        end
    end

endmodule

`default_nettype wire
