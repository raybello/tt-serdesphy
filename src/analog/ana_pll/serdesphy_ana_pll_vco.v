/*
 * SerDes PHY PLL VCO
 * Synthesis: constant-0 placeholder (replaced by analog ring oscillator in silicon).
 * Simulation: behavioral oscillator with frequency control modeling.
 *
 * vco_control[7:0] structure:
 *   [7:4] - Coarse tuning (from vco_trim register)
 *   [3:0] - Fine tuning (from loop filter)
 *
 * Frequency modeling:
 *   - Nominal: 240 MHz at vco_control = 8'h80 (mid-range)
 *   - Coarse step: ±5 MHz per coarse bit (~±80 MHz total range)
 *   - Fine step: ±312.5 kHz per fine bit (~±5 MHz total fine range)
 *   - Total range: ~160 MHz to ~320 MHz
 */

`default_nettype none

module serdesphy_ana_pll_vco (
    input  wire       rst_n,
    input  wire       enable,
    input  wire [7:0] vco_control,
    output reg        vco_out,
    output wire       vco_ready
);

`ifndef SYNTHESIS
    // Simulation-only behavioral oscillator with frequency modeling

    localparam real NOMINAL_FREQ_MHZ = 240.0;
    localparam real COARSE_STEP_MHZ = 5.0;
    localparam real FINE_STEP_MHZ = 0.3125;

    real current_half_period_ns;
    event vco_restart;
    integer last_vco_control;

    initial begin
        vco_out = 1'b0;
        last_vco_control = 0;
    end

    // Calculate half-period from vco_control
    function real calc_half_period;
        input [7:0] ctrl;
        integer coarse, fine;
        real freq;
        begin
            coarse = ctrl[7:4];
            fine = ctrl[3:0];
            freq = NOMINAL_FREQ_MHZ + (coarse - 8) * COARSE_STEP_MHZ + (fine - 8) * FINE_STEP_MHZ;
            calc_half_period = (freq > 0) ? (500.0 / freq) : 2.083;
        end
    endfunction

    // Detect vco_control changes and restart oscillator
    always @(vco_control) begin
        if (vco_control !== last_vco_control) begin
            last_vco_control = vco_control;
            $display("[VCO] @ %0t ns: vco_control changed to 0x%0h (coarse=%0d, fine=%0d) freq=%0.2f MHz",
                     $realtime/1000.0, vco_control, vco_control[7:4], vco_control[3:0],
                     NOMINAL_FREQ_MHZ + (vco_control[7:4] - 8) * COARSE_STEP_MHZ + (vco_control[3:0] - 8) * FINE_STEP_MHZ);
            -> vco_restart;  // Trigger restart
        end
    end

    // Main oscillator - restarts with new frequency on control change
    always @(vco_restart or posedge enable or negedge rst_n) begin
        vco_out = 1'b0;  // Reset output on restart
        current_half_period_ns = calc_half_period(vco_control);

        while (enable && rst_n) begin
            // Check if control changed during delay
            current_half_period_ns = calc_half_period(vco_control);
            #(current_half_period_ns * 1ns);
            if (enable && rst_n)  // Check again after delay
                vco_out = ~vco_out;
            else
                break;
        end

        if (!enable || !rst_n)
            vco_out = 1'b0;
    end

`else
    // Synthesis placeholder
    assign vco_out = 1'b0;
`endif

    assign vco_ready = rst_n & enable;

endmodule

`default_nettype wire
