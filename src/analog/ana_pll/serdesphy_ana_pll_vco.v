/*
 * SerDes PHY PLL VCO
 * Synthesis: constant-0 placeholder (replaced by analog ring oscillator in silicon).
 * Simulation: behavioral oscillator with frequency control modeling.
 *
 * Frequency modeling:
 *   - vco_control: 8-bit dynamic control from loop filter (0-255, nominal=128)
 *   - vco_trim: 4-bit static coarse offset (0-15, nominal=8)
 *   - Fine step: 312.5 kHz per vco_control step (±40 MHz total fine range)
 *   - Coarse step: 5 MHz per vco_trim step (±40 MHz total coarse range)
 *   - Nominal: 240 MHz at vco_control=128, vco_trim=8
 *   - Total range: ~160 MHz to ~320 MHz
 */

`default_nettype none

module serdesphy_ana_pll_vco (
    input  wire       rst_n,
    input  wire       enable,
    input  wire [7:0] vco_control,     // From loop filter (0-255, centered at 128)
    input  wire [3:0] vco_trim,        // Static coarse offset (0-15, nominal=8)
    output reg        vco_out,
    output wire       vco_ready
);

`ifndef SYNTHESIS
    // Simulation-only behavioral oscillator with frequency modeling

    localparam real NOMINAL_FREQ_MHZ = 240.0;
    localparam real COARSE_STEP_MHZ = 5.0;
    localparam real FINE_STEP_MHZ = 0.3125;  // 80 MHz / 256 steps = 312.5 kHz/step (±40 MHz range)

    real current_half_period_ns;
    event vco_restart;
    integer last_vco_control;
    integer last_vco_trim;

    initial begin
        vco_out = 1'b0;
        last_vco_control = 0;
        last_vco_trim = 0;
    end

    // Calculate half-period from vco_control and vco_trim
    function real calc_half_period;
        input [7:0] ctrl;
        input [3:0] trim;
        integer ctrl_int, trim_int;
        real coarse_off, fine_off, freq;
        begin
            ctrl_int = ctrl;     // 0-255
            trim_int = trim;     // 0-15

            // Calculate offsets (centered at ctrl=128, trim=8)
            fine_off = (ctrl_int - 128) * FINE_STEP_MHZ;
            coarse_off = (trim_int - 8) * COARSE_STEP_MHZ;

            freq = NOMINAL_FREQ_MHZ + coarse_off + fine_off;
            calc_half_period = (freq > 0.0) ? (500.0 / freq) : 2.083;
        end
    endfunction

    // Detect vco_control or vco_trim changes and restart oscillator
    always @(vco_control or vco_trim) begin
        if (vco_control !== last_vco_control || vco_trim !== last_vco_trim) begin
            integer ctrl_val, trim_val;
            real freq_calc;
            last_vco_control = vco_control;
            last_vco_trim = vco_trim;
            ctrl_val = vco_control;
            trim_val = vco_trim;
            freq_calc = NOMINAL_FREQ_MHZ + (trim_val - 8) * COARSE_STEP_MHZ + (ctrl_val - 128) * FINE_STEP_MHZ;
            $display("[VCO] @ %0.3f us: vco_trim=%0d vco_control=0x%0h (%0d) freq=%0.2f MHz",
                     $realtime/1000000.0, trim_val, vco_control, ctrl_val, freq_calc);
            -> vco_restart;  // Trigger restart
        end
    end

    // Main oscillator - restarts with new frequency on control change
    always @(vco_restart or posedge enable or negedge rst_n) begin
        vco_out = 1'b0;  // Reset output on restart
        current_half_period_ns = calc_half_period(vco_control, vco_trim);

        while (enable && rst_n) begin
            // Check if control changed during delay
            current_half_period_ns = calc_half_period(vco_control, vco_trim);
            #(current_half_period_ns * 1ns);
            if (enable && rst_n)  // Check again after delay
                vco_out = ~vco_out;
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
