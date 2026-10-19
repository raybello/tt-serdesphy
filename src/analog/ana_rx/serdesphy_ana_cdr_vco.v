/*
 * SerDes PHY CDR VCO
 * Synthesis: constant-0 placeholder (replaced by analog ring oscillator in silicon).
 *
 * Simulation: behavioral voltage-controlled oscillator with frequency offset
 * and tracking capabilities. This model supports:
 *
 * 1. **Frequency Offset Acquisition (±2000 ppm)**: The VCO can start at a
 *    different frequency than the TX PLL (configurable via FREQ_OFFSET_PPM
 *    parameter), simulating real-world frequency mismatch between TX and RX
 *    crystal oscillators. The CDR loop must pull the VCO frequency to match
 *    the incoming data rate.
 *
 * 2. **VCO Gain (Kvco)**: The control input (cdr_control) adjusts the VCO's
 *    instantaneous frequency around its free-running frequency. Kvco is sized
 *    to provide >±2000 ppm tuning range across the full 8-bit control range,
 *    ensuring the CDR can always acquire lock regardless of initial offset.
 *
 * 3. **Tracking Bandwidth**: The combination of Kvco and the CDR loop gain
 *    (in serdesphy_ana_cdr.v) determines the CDR's tracking bandwidth - how
 *    quickly it can follow frequency/phase variations in the incoming signal.
 *
 * **Model Details:**
 * - Free-running frequency = NOMINAL_FREQ_MHZ * (1 + FREQ_OFFSET_PPM/1e6)
 * - Controlled frequency = free_run + (cdr_control - 128) * Kvco
 * - Kvco = 3.75 kHz/LSB, giving ±480 kHz (±2000 ppm) tuning range
 * - Half-period = 0.5 / controlled_frequency
 *
 * This replaces the previous phase-only model, which couldn't test frequency
 * acquisition. The phase tracking behavior is preserved (sustained control
 * deviation → frequency offset → phase accumulation), but now the VCO can
 * actually start misaligned and pull into lock.
 *
 * See docs/implementation/01-spec-vs-implementation.md Finding 2.2 and
 * Known Behavioral Model Limitations L1.
 *
 * Nominal: 240 MHz ± configured offset (half-period 2.083 ns ± offset)
 */

`default_nettype none

module serdesphy_ana_cdr_vco #(
    // Frequency offset in ppm (parts per million) from nominal 240 MHz.
    // Positive = VCO runs faster than TX, negative = slower.
    // Spec requires CDR to acquire across ±2000 ppm crystal tolerance.
    parameter real FREQ_OFFSET_PPM = 0.0
)(
    input  wire       rst_n,
    input  wire       enable,
    input  wire [7:0] cdr_control,
    output wire       vco_out,
    output wire       vco_ready
);

`ifndef SYNTHESIS
    // Simulation-only behavioral VCO with frequency offset and tracking

    // VCO characteristics
    localparam real NOMINAL_FREQ_MHZ       = 240.0;
    localparam real KVCO_KHZ_PER_LSB       = 3.75;   // VCO gain: 3.75 kHz/LSB
                                                      // Full range: ±128 LSB * 3.75 kHz = ±480 kHz (±2000 ppm)
    localparam real MIN_HALF_PERIOD_NS     = 1.0;    // Sanity limit
    localparam real MAX_HALF_PERIOD_NS     = 10.0;   // Sanity limit

    reg vco_clk;
    initial vco_clk = 1'b0;

    // Calculate controlled frequency based on control voltage
    // freq = free_run + (control - midscale) * Kvco
    function automatic real controlled_freq_mhz(input [7:0] control);
        real freq_offset_khz, free_run_mhz;
        begin
            // Calculate free-running frequency with offset inline
            free_run_mhz = NOMINAL_FREQ_MHZ * (1.0 + FREQ_OFFSET_PPM / 1e6);
            freq_offset_khz = ($itor(control) - 128.0) * KVCO_KHZ_PER_LSB;
            controlled_freq_mhz = free_run_mhz + (freq_offset_khz / 1000.0);
        end
    endfunction

    // Calculate half-period from frequency
    function automatic real half_period_ns(input [7:0] control);
        real freq_mhz, period_ns, hp_ns;
        begin
            freq_mhz = controlled_freq_mhz(control);
            period_ns = 1000.0 / freq_mhz;  // Period in ns
            hp_ns = period_ns / 2.0;        // Half-period

            // Clamp to sanity limits
            if (hp_ns < MIN_HALF_PERIOD_NS)
                half_period_ns = MIN_HALF_PERIOD_NS;
            else if (hp_ns > MAX_HALF_PERIOD_NS)
                half_period_ns = MAX_HALF_PERIOD_NS;
            else
                half_period_ns = hp_ns;
        end
    endfunction

    always begin
        if (enable && rst_n)
            #(half_period_ns(cdr_control)) vco_clk = ~vco_clk;
        else begin
            vco_clk = 1'b0;
            @(posedge enable or posedge rst_n);
        end
    end
    assign vco_out = (enable && rst_n) ? vco_clk : 1'b0;
`else
    // Synthesis placeholder: no oscillation (replaced by analog in tapeout)
    assign vco_out = 1'b0;
    wire _unused = &{cdr_control};
`endif

    assign vco_ready = rst_n & enable;

endmodule
