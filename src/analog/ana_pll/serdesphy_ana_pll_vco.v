/*
 * SerDes PHY PLL VCO
 * Synthesis: constant-0 placeholder (replaced by analog ring oscillator in silicon).
 * Simulation: behavioral 240 MHz oscillator with frequency control modeling.
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
 *
 * Implementation: Phase accumulator model for proper frequency control
 */

`default_nettype none

module serdesphy_ana_pll_vco (
    input  wire       rst_n,
    input  wire       enable,
    input  wire [7:0] vco_control,
    output wire       vco_out,
    output wire       vco_ready
);

`ifndef SYNTHESIS
    // Simulation-only behavioral oscillator with frequency modeling

    // Frequency calculation parameters
    localparam real NOMINAL_FREQ_MHZ = 240.0;
    localparam real COARSE_STEP_MHZ = 5.0;    // 5 MHz per coarse bit
    localparam real FINE_STEP_MHZ = 0.3125;   // 312.5 kHz per fine bit

    // Phase accumulator approach - updates at high rate to model frequency
    // Using 1ps timestep for smooth frequency control
    localparam real UPDATE_PERIOD_NS = 0.001;  // 1ps updates for smooth operation

    reg vco_clk;
    real phase_accum;
    real freq_mhz;
    real phase_increment;
    integer coarse, fine;

    initial begin
        vco_clk = 1'b0;
        phase_accum = 0.0;
    end

    // Calculate current frequency from vco_control
    always @(*) begin
        coarse = vco_control[7:4];
        fine = vco_control[3:0];

        // Frequency = nominal + coarse_offset + fine_offset
        // Both centered at 8 (mid-range of 0-15)
        freq_mhz = NOMINAL_FREQ_MHZ +
                   (coarse - 8) * COARSE_STEP_MHZ +
                   (fine - 8) * FINE_STEP_MHZ;

        // Phase increment per update period (in cycles)
        // freq_mhz * UPDATE_PERIOD_NS * 1e-3 = cycles per update
        phase_increment = freq_mhz * UPDATE_PERIOD_NS * 1e-3;
    end

    // Phase accumulator running at fixed update rate
    always begin
        if (!enable || !rst_n) begin
            phase_accum = 0.0;
            vco_clk = 1'b0;
            @(posedge enable or posedge rst_n);
        end else begin
            #(UPDATE_PERIOD_NS * 1ns);
            phase_accum = phase_accum + phase_increment;

            // Generate clock output from phase
            if (phase_accum >= 0.5) begin
                phase_accum = phase_accum - 1.0;
                vco_clk = ~vco_clk;
            end
        end
    end

    assign vco_out = (enable && rst_n) ? vco_clk : 1'b0;
`else
    // Synthesis placeholder: no oscillation (replaced by analog in tapeout)
    assign vco_out = 1'b0;
`endif

    assign vco_ready = rst_n & enable;

endmodule

`default_nettype wire
