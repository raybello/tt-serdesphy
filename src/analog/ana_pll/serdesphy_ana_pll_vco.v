/*
 * SerDes PHY PLL VCO
 * Behavioral RTL model for simulation
 * Generates 240 MHz nominal clock with tunable frequency
 *
 * Mathematical Model:
 *   frequency = f_center + (vco_control - 128) * f_step
 *   f_center = 240 MHz (nominal)
 *   f_step = 0.5 MHz per LSB
 *   Range: ~176 MHz to ~304 MHz
 *
 *   period_ns = 1000 / frequency_mhz
 *   At 240 MHz: period = 4.167 ns, half_period = 2.083 ns
 */

`default_nettype none
`timescale 1ns/1ps

module serdesphy_ana_pll_vco (
    // Clock and reset
    input  wire       rst_n,           // Active-low reset
    input  wire       enable,          // VCO enable

    // Control input
    input  wire [7:0]  vco_control,    // VCO control voltage (0-255)

    // Output
    output wire       vco_out,         // VCO output clock
    output wire       vco_ready        // VCO stable flag
);

    // Internal state
    reg        vco_out_reg;
    reg        vco_ready_reg;
    reg [31:0] startup_counter;

    // VCO frequency calculation
    // Nominal 240 MHz = 4.167 ns period = 2.083 ns half-period
    // Control range: vco_control 0-255, center at 128
    // Frequency adjustment: +/- 64 MHz from center

    real half_period_ns;
    real frequency_mhz;

    // Calculate frequency based on control voltage
    always @(vco_control) begin
        // f = 240 + (vco_control - 128) * 0.5 MHz
        frequency_mhz = 240.0 + ($signed({1'b0, vco_control}) - 128) * 0.5;

        // Clamp to valid range (176-304 MHz)
        if (frequency_mhz < 176.0) frequency_mhz = 176.0;
        if (frequency_mhz > 304.0) frequency_mhz = 304.0;

        // Calculate half period in nanoseconds
        half_period_ns = 1000.0 / (2.0 * frequency_mhz);
    end

    // Startup delay - VCO needs time to stabilize (~100 cycles)
    always @(posedge vco_out_reg or negedge rst_n) begin
        if (!rst_n) begin
            startup_counter <= 32'd0;
            vco_ready_reg <= 1'b0;
        end else if (!enable) begin
            startup_counter <= 32'd0;
            vco_ready_reg <= 1'b0;
        end else if (startup_counter < 32'd100) begin
            startup_counter <= startup_counter + 1;
            vco_ready_reg <= 1'b0;
        end else begin
            vco_ready_reg <= 1'b1;
        end
    end

    // VCO oscillator - generates clock based on control voltage
    // This is a behavioral model using time delays
    initial begin
        vco_out_reg = 1'b0;
        half_period_ns = 2.083; // Default 240 MHz
    end

    always begin
        if (!rst_n || !enable) begin
            vco_out_reg = 1'b0;
            // @(posedge rst_n or posedge enable);
            // #1; // Small delay after enable
        end else begin
            // #(half_period_ns);
            vco_out_reg = ~vco_out_reg;
        end
    end

    // Output assignments
    assign vco_out = vco_out_reg;
    assign vco_ready = vco_ready_reg;

endmodule