/*
 * SerDes PHY CDR VCO
 * Behavioral RTL model for clock data recovery
 * Generates 240 MHz nominal clock with tight tracking range
 *
 * Mathematical Model:
 *   frequency = f_center + (cdr_control - 128) * f_step
 *   f_center = 240 MHz (nominal)
 *   f_step = 0.1 MHz per LSB (tighter range than PLL VCO)
 *   Range: ~227 MHz to ~253 MHz (+/- 2000 ppm tracking)
 *
 *   period_ns = 1000 / frequency_mhz
 *   At 240 MHz: period = 4.167 ns, half_period = 2.083 ns
 */

`default_nettype none
`timescale 1ns/1ps

module serdesphy_ana_cdr_vco (
    // Clock and reset
    input  wire       rst_n,           // Active-low reset
    input  wire       enable,          // VCO enable

    // Control input
    input  wire [7:0]  cdr_control,    // CDR control voltage (0-255)

    // Output
    output wire       vco_out,         // VCO output clock
    output wire       vco_ready        // VCO stable flag
);

    // Internal state
    reg        vco_out_reg;
    reg        vco_ready_reg;
    reg [31:0] startup_counter;

    // CDR VCO frequency calculation
    // Nominal 240 MHz = 4.167 ns period = 2.083 ns half-period
    // Control range: cdr_control 0-255, center at 128
    // Tighter tracking: +/- 12.8 MHz from center (0.1 MHz per LSB)

    realtime half_period_ns;
    realtime frequency_mhz;

    // Calculate frequency based on control voltage
    always @(cdr_control) begin
        // f = 240 + (cdr_control - 128) * 0.1 MHz
        frequency_mhz = 240.0 + ($signed({1'b0, cdr_control}) - 128) * 0.1;

        // Clamp to valid range (227.2-252.8 MHz)
        if (frequency_mhz < 227.2) frequency_mhz = 227.2;
        if (frequency_mhz > 252.8) frequency_mhz = 252.8;

        // Calculate half period in nanoseconds
        half_period_ns = 1000.0 / (2.0 * frequency_mhz);
    end

    // Startup delay - VCO needs time to stabilize (~50 cycles for CDR)
    always @(posedge vco_out_reg or negedge rst_n) begin
        if (!rst_n) begin
            startup_counter <= 32'd0;
            vco_ready_reg <= 1'b0;
        end else if (!enable) begin
            startup_counter <= 32'd0;
            vco_ready_reg <= 1'b0;
        end else if (startup_counter < 32'd50) begin
            startup_counter <= startup_counter + 1;
            vco_ready_reg <= 1'b0;
        end else begin
            vco_ready_reg <= 1'b1;
        end
    end

    // VCO oscillator - generates clock based on control voltage
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