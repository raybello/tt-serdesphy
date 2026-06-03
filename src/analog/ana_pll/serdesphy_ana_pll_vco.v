/*
 * SerDes PHY PLL VCO
 * Synthesis: constant-0 placeholder (replaced by analog ring oscillator in silicon).
 * Simulation: behavioral 240 MHz oscillator so the TX serializer has a clock.
 *
 * Nominal: 240 MHz (half-period 2.083 ns, 1 ns/1 ps timescale)
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
    // Simulation-only behavioral oscillator
    reg vco_clk;
    initial vco_clk = 1'b0;
    always begin
        if (enable && rst_n)
            #2.083 vco_clk = ~vco_clk;
        else begin
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

    // Unused input - prevent lint warnings
    wire _unused = &{vco_control};

endmodule
