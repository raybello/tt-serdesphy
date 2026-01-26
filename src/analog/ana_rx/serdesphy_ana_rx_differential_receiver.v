/*
 * SerDes PHY RX Differential Receiver
 * Behavioral RTL model - Limiting amplifier with hysteresis
 *
 * Features:
 *   - Differential to single-ended conversion
 *   - ~10 mV sensitivity (modeled as digital threshold)
 *   - Hysteresis for noise immunity
 *   - Signal detection flag
 *   - Loopback input support
 *
 * Operation:
 *   - Compares RXP vs RXN differential inputs
 *   - Uses hysteresis to prevent glitches
 *   - Signal detected when valid differential signal present
 */

`default_nettype none

module serdesphy_ana_rx_differential_receiver (
    // Clock and reset
    input  wire       clk,             // System clock (240 MHz)
    input  wire       rst_n,           // Active-low reset
    input  wire       enable,          // Enable receiver

    // Differential inputs
    input  wire       rxp,             // RX differential (+)
    input  wire       rxn,             // RX differential (-)

    // Control inputs
    input  wire       iso_en,          // Analog isolation enable
    input  wire       lpbk_en,         // Loopback enable

    // Loopback inputs (directly from TX driver for internal loopback)
    input  wire       lpbk_txp,        // Loopback TX+ input
    input  wire       lpbk_txn,        // Loopback TX- input

    // Single-ended output
    output wire       serial_data,     // Single-ended serial data output
    output wire       signal_detected  // Signal detected flag
);

    // Internal registers
    reg serial_data_reg;
    reg signal_detected_reg;
    reg current_state;  // For hysteresis

    // Muxed differential inputs (loopback or external)
    wire rxp_mux;
    wire rxn_mux;

    // Select loopback or external input
    assign rxp_mux = lpbk_en ? lpbk_txp : rxp;
    assign rxn_mux = lpbk_en ? lpbk_txn : rxn;

    // Differential receiver with hysteresis model
    // In digital simulation, we detect differential state directly
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            serial_data_reg <= 1'b0;
            signal_detected_reg <= 1'b0;
            current_state <= 1'b0;
        end else if (!enable || iso_en) begin
            // Isolated or disabled - output low, no signal
            serial_data_reg <= 1'b0;
            signal_detected_reg <= 1'b0;
            current_state <= 1'b0;
        end else begin
            // Differential detection with hysteresis
            // RXP > RXN means logic 1, RXP < RXN means logic 0
            if (rxp_mux && !rxn_mux) begin
                // Clear differential high
                serial_data_reg <= 1'b1;
                signal_detected_reg <= 1'b1;
                current_state <= 1'b1;
            end else if (!rxp_mux && rxn_mux) begin
                // Clear differential low
                serial_data_reg <= 1'b0;
                signal_detected_reg <= 1'b1;
                current_state <= 1'b0;
            end else if (rxp_mux == rxn_mux) begin
                // Common mode - hold previous state (hysteresis)
                // This models the receiver holding its output when
                // signal is in transition or has no differential
                serial_data_reg <= current_state;
                // Signal detect goes low only after sustained common mode
                signal_detected_reg <= 1'b0;
            end
        end
    end

    // Output assignments
    assign serial_data = serial_data_reg;
    assign signal_detected = signal_detected_reg;

endmodule