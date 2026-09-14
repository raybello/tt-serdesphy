/*
 * SerDes PHY CDR VCO
 * Synthesis: constant-0 placeholder (replaced by analog ring oscillator in silicon).
 *
 * Simulation: behavioral 240 MHz oscillator whose EDGE TIMING actually
 * responds to cdr_control, so the bang-bang phase detector in
 * serdesphy_ana_cdr.v can genuinely pull this clock's sampling edges
 * into alignment with the incoming data - see
 * docs/implementation/01-spec-vs-implementation.md Finding 2.2 and
 * docs/implementation/cdr_vco/README.md section 5. Previously this
 * model ignored cdr_control entirely (fixed period, free-running), which
 * only worked because serdesphy_pma.v separately hard-wired clk_240m_cdr
 * to the TX PLL's own clock instead of this VCO's output - i.e. there
 * was no real clock recovery happening in simulation at all. Now that
 * clk_240m_cdr is this VCO's real output, it has to actually track.
 *
 * Model: each half-period is nudged by GAIN_PS_PER_LSB times the signed
 * deviation of cdr_control from mid-scale (8'h80), applied every
 * half-cycle. A sustained deviation (the phase detector consistently
 * calling early or late) therefore accumulates a persistent phase shift
 * over many cycles - exactly how a real bang-bang CDR's VCO integrates
 * its phase detector's decisions into a frequency/phase correction.
 * Once locked, phase_detector_reg dithers near mid-scale, so the average
 * correction is ~0 and the recovered clock holds steady, matching real
 * bang-bang CDR behavior.
 *
 * Nominal: 240 MHz (half-period 2.083 ns, 1 ns/1 ps timescale).
 */

`default_nettype none

module serdesphy_ana_cdr_vco (
    input  wire       rst_n,
    input  wire       enable,
    input  wire [7:0] cdr_control,
    output wire       vco_out,
    output wire       vco_ready
);

`ifndef SYNTHESIS
    // Simulation-only behavioral oscillator with phase-tracking control
    localparam real NOMINAL_HALF_PERIOD_NS = 2.083;
    localparam real GAIN_PS_PER_LSB        = 0.4;
    localparam real MIN_HALF_PERIOD_NS     = 1.0;

    reg vco_clk;
    initial vco_clk = 1'b0;

    function automatic real half_period_ns(input [7:0] control);
        real deviation, adj_ns, result;
        begin
            deviation   = $itor(control) - 128.0;
            adj_ns      = (deviation * GAIN_PS_PER_LSB) / 1000.0;
            result      = NOMINAL_HALF_PERIOD_NS + adj_ns;
            half_period_ns = (result < MIN_HALF_PERIOD_NS) ? MIN_HALF_PERIOD_NS : result;
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
