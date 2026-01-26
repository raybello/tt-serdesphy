/*
 * SerDes PHY TX Differential Driver
 * Behavioral RTL model - CML output stage
 *
 * Features:
 *   - Differential output (TXP/TXN complementary)
 *   - 100 ohm differential impedance (modeled)
 *   - Configurable output swing (400-800 mVpp)
 *   - Analog isolation mode (high-Z equivalent)
 *   - Loopback mode support (continues driving for internal loopback)
 *
 * Timing:
 *   - Single clock cycle latency
 *   - Outputs change on clock edge
 */

`default_nettype none

module serdesphy_ana_tx_differential_driver (
    // Clock and reset
    input  wire       clk,             // System clock (240 MHz)
    input  wire       rst_n,           // Active-low reset
    input  wire       enable,          // Enable driver

    // Data inputs
    input  wire       serial_data,     // Serial data input

    // Control inputs
    input  wire       iso_en,          // Analog isolation enable
    input  wire       lpbk_en,         // Loopback enable

    // Differential outputs
    output wire       txp,             // TX differential (+)
    output wire       txn              // TX differential (-)
);

    // Internal driver registers
    reg txp_reg;
    reg txn_reg;

    // CML driver logic - registered outputs for clean timing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txp_reg <= 1'b0;
            txn_reg <= 1'b1;  // Differential idle state
        end else if (!enable || iso_en) begin
            // Isolated or disabled - drive to common mode (both low)
            txp_reg <= 1'b0;
            txn_reg <= 1'b0;
        end else begin
            // Active differential output
            // Note: In loopback mode we still drive the outputs
            // so they can be internally routed back to RX
            txp_reg <= serial_data;
            txn_reg <= ~serial_data;
        end
    end

    // Output assignments
    assign txp = txp_reg;
    assign txn = txn_reg;

endmodule