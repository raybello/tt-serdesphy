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
    // Nominal frequency: 240 MHz (period = 4.166 ns, half-period = 2.083 ns)
    localparam real NOMINAL_FREQ_MHZ = 240.0;
    localparam real NOMINAL_CONTROL = 128.0;  // Mid-range of 8-bit control

    // Tuning ranges
    localparam real COARSE_STEP_MHZ = 5.0;    // 5 MHz per coarse bit
    localparam real FINE_STEP_MHZ = 0.3125;   // 312.5 kHz per fine bit

    reg vco_clk;
    real current_freq_mhz;
    real current_half_period_ns;
    integer coarse_control;
    integer fine_control;
    real coarse_offset_mhz;
    real fine_offset_mhz;

    initial vco_clk = 1'b0;

    // Calculate frequency based on control inputs
    always @(*) begin
        // Extract coarse and fine controls
        coarse_control = vco_control[7:4];
        fine_control = vco_control[3:0];

        // Calculate frequency offsets from nominal
        // Coarse: centered around 8 (0-15 range)
        coarse_offset_mhz = (coarse_control - 8) * COARSE_STEP_MHZ;

        // Fine: centered around 8 (0-15 range)
        fine_offset_mhz = (fine_control - 8) * FINE_STEP_MHZ;

        // Total frequency
        current_freq_mhz = NOMINAL_FREQ_MHZ + coarse_offset_mhz + fine_offset_mhz;

        // Convert to half-period in ns
        // Half-period = 1 / (2 * freq_MHz * 1e-3)
        if (current_freq_mhz > 0)
            current_half_period_ns = 500.0 / current_freq_mhz;
        else
            current_half_period_ns = 2.083; // Default to nominal
    end

    // VCO oscillation with variable frequency
    always begin
        if (enable && rst_n) begin
            #(current_half_period_ns * 1ns) vco_clk = ~vco_clk;
        end else begin
            vco_clk = 1'b0;
            @(posedge enable or posedge rst_n);
        end
    end

    assign vco_out = (enable && rst_n) ? vco_clk : 1'b0;
`else
    // Synthesis placeholder: no oscillation (replaced by analog in tapeout)
    assign vco_out = 1'b0;
`endif

    assign vco_ready = rst_n & enable;

endmodule
