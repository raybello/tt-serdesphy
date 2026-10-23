/*
 * SerDes PHY PLL
 *
 * Behavioral charge-pump PLL: PFD -> signed charge pump -> VCO-clocked loop
 * filter -> continuous VCO -> divide-by-10 feedback.
 *
 * A frequency counter runs alongside the phase loop. It measures the VCO edge
 * count over a 32-reference-cycle window (320 edges at 240 MHz / 24 MHz) and
 * is used both to widen acquisition and as the lock metric. PLL_LOCK therefore
 * means "the output frequency is within +/-2%" rather than "the loop filter
 * happened to stop moving".
 *
 * All numeric constants are behavioral-model choices, not silicon values:
 *   - 32-cycle frequency window (~1.33 us at 24 MHz)
 *   - +/-6 VCO edges = +/-1.875% frequency error
 *   - 2 consecutive good/bad windows for lock/unlock hysteresis
 */

`default_nettype none
`timescale 1ns / 1ps

module serdesphy_ana_pll (
    input  wire       clk_ref_24m,
    input  wire       rst_n,
    input  wire       pll_rst,
    input  wire       pll_bypass,
    input  wire       enable,

    input  wire [3:0] vco_trim,
    input  wire [1:0] cp_current,

    output wire       clk_240m_out,
    output wire       pll_lock,
    output wire [7:0] vco_control
);

    localparam integer FREQ_WINDOW        = 32;    // reference cycles
    localparam integer FREQ_EXPECTED      = 320;   // VCO edges per window at 10x
    localparam integer FREQ_LOCK_TOLERANCE = 6;    // +/-1.875% at 320 edges
    localparam integer LOCK_WINDOWS       = 2;

    wire             phase_det_up;
    wire             phase_det_down;
    wire signed [4:0] charge_pump_out;
    wire [7:0]       loop_filter_out;
    wire             vco_out;
    wire             vco_ready;
    wire             divider_output;
    wire             divider_pulse;
    wire             feedback_clk;
    wire             analog_enable;

    reg [5:0]        ref_window_count;
    reg [9:0]        vco_edge_count;
    reg signed [9:0] freq_error;
    reg              freq_valid;
    reg              window_toggle;
    reg              window_toggle_d;

    reg [3:0]        good_windows;
    reg [3:0]        bad_windows;
    reg              pll_lock_reg;

    initial begin
        ref_window_count = 6'd0;
        vco_edge_count   = 10'd0;
        freq_error       = 9'sd0;
        freq_valid       = 1'b0;
        window_toggle    = 1'b0;
        window_toggle_d  = 1'b0;
        good_windows     = 4'd0;
        bad_windows      = 4'd0;
        pll_lock_reg     = 1'b0;
    end

    assign analog_enable = enable && !pll_bypass;

    // ---------------------------------------------------------------------
    // Phase/frequency detector and charge pump
    // ---------------------------------------------------------------------
    serdesphy_ana_phase_frequency_detector u_phase_det (
        .clk_ref      (clk_ref_24m),
        .clk_feedback (feedback_clk),
        .rst_n        (rst_n && !pll_rst),
        .enable       (analog_enable),
        .up_pulse     (phase_det_up),
        .down_pulse   (phase_det_down)
    );

    serdesphy_ana_pll_charge_pump u_charge_pump (
        .clk         (clk_ref_24m),
        .rst_n       (rst_n),
        .enable      (analog_enable),
        .cp_current  (cp_current),
        .up_pulse    (phase_det_up),
        .down_pulse  (phase_det_down),
        .charge_out  (charge_pump_out)
    );

    // ---------------------------------------------------------------------
    // VCO (continuous phase) and feedback divider
    // ---------------------------------------------------------------------
    serdesphy_ana_pll_vco u_vco (
        .rst_n       (rst_n),
        .enable      (analog_enable),
        .vco_control (loop_filter_out),
        .vco_trim    (vco_trim),
        .vco_out     (vco_out),
        .vco_ready   (vco_ready)
    );

    serdesphy_ana_frequency_divider u_frequency_divider (
        .clk_in      (vco_out),
        .rst_n       (rst_n),
        .enable      (analog_enable),
        .clk_out     (divider_output),
        .clk_divided (divider_pulse)
    );

    assign feedback_clk = divider_output;

    // ---------------------------------------------------------------------
    // Loop filter - clocked by the VCO so UP/DN pulse widths are integrated
    // ---------------------------------------------------------------------
    serdesphy_ana_pll_loop_filter u_loop_filter (
        .clk         (vco_out),
        .rst_n       (rst_n),
        .enable      (analog_enable),
        .charge_in   (charge_pump_out),
        .freq_error  (freq_error),
        .freq_valid  (freq_valid),
        .vco_control (loop_filter_out)
    );

    // ---------------------------------------------------------------------
    // Frequency counter and lock detector
    // ---------------------------------------------------------------------
    always @(posedge vco_out or negedge rst_n) begin
        if (!rst_n) begin
            vco_edge_count  <= 10'd0;
            window_toggle_d <= 1'b0;
        end else if (!analog_enable) begin
            vco_edge_count  <= 10'd0;
            window_toggle_d <= window_toggle;
        end else begin
            window_toggle_d <= window_toggle;
            if (window_toggle != window_toggle_d)
                vco_edge_count <= 10'd1;   // count this edge in the new window
            else
                vco_edge_count <= vco_edge_count + 1'b1;
        end
    end

    always @(posedge clk_ref_24m or negedge rst_n) begin
        if (!rst_n) begin
            ref_window_count <= 6'd0;
            freq_error       <= 9'sd0;
            freq_valid       <= 1'b0;
            window_toggle    <= 1'b0;
        end else if (!analog_enable) begin
            ref_window_count <= 6'd0;
            freq_error       <= 9'sd0;
            freq_valid       <= 1'b0;
            window_toggle    <= 1'b0;
        end else if (ref_window_count == FREQ_WINDOW - 1) begin
            freq_error       <= FREQ_EXPECTED - $signed({1'b0, vco_edge_count});
            freq_valid       <= 1'b1;
            ref_window_count <= 6'd0;
            window_toggle    <= ~window_toggle;
        end else begin
            ref_window_count <= ref_window_count + 1'b1;
            freq_valid       <= 1'b0;
        end
    end

    always @(posedge clk_ref_24m or negedge rst_n) begin
        if (!rst_n) begin
            good_windows <= 4'd0;
            bad_windows  <= 4'd0;
            pll_lock_reg <= 1'b0;
        end else if (!analog_enable || pll_rst) begin
            good_windows <= 4'd0;
            bad_windows  <= 4'd0;
            pll_lock_reg <= 1'b0;
        end else if (freq_valid) begin
            if (freq_error <= FREQ_LOCK_TOLERANCE &&
                freq_error >= -FREQ_LOCK_TOLERANCE) begin
                bad_windows <= 4'd0;
                if (good_windows < LOCK_WINDOWS)
                    good_windows <= good_windows + 1'b1;
                if (good_windows >= LOCK_WINDOWS - 1)
                    pll_lock_reg <= 1'b1;
            end else begin
                good_windows <= 4'd0;
                if (bad_windows < LOCK_WINDOWS)
                    bad_windows <= bad_windows + 1'b1;
                if (bad_windows >= LOCK_WINDOWS - 1)
                    pll_lock_reg <= 1'b0;
            end
        end
    end

    assign clk_240m_out = pll_bypass ? clk_ref_24m : vco_out;
    assign pll_lock     = pll_lock_reg && !pll_bypass && vco_ready;
    assign vco_control  = loop_filter_out;

endmodule

`default_nettype wire
