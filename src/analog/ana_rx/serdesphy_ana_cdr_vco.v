/*
 * SerDes PHY CDR VCO
 * Behavioral simulation model - generates ~240 MHz clock when enabled
 * In production this will be replaced with an analog oscillator.
 *
 * Nominal: 240 MHz (half-period ≈ 2.083 ns with 1 ns/1 ps timescale)
 * Range:   ~227–253 MHz tracked by CDR loop (not modelled here)
 */

`default_nettype none

module serdesphy_ana_cdr_vco (
    input  wire       rst_n,
    input  wire       enable,
    input  wire [7:0] cdr_control,
    output wire       vco_out,
    output wire       vco_ready
);

    // Behavioral oscillator: toggles at ~240 MHz when enabled
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

    assign vco_out   = (enable && rst_n) ? vco_clk : 1'b0;
    assign vco_ready = rst_n & enable;

    // Unused input - prevent lint warnings
    wire _unused = &{cdr_control};

endmodule
