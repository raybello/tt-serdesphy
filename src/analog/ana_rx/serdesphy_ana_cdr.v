/*
 * SerDes PHY CDR (Clock Data Recovery)
 * Phase Detector with Frequency Tracking via Phase Accumulation
 *
 * This CDR combines:
 * - Alexander-style bang-bang phase detector for phase tracking
 * - Frequency detector: accumulates phase error over a window
 * - PI loop filter with carefully tuned gains
 *
 * Key: Frequency offset causes phase to DRIFT over time. By accumulating
 * phase errors over a window, we can detect this drift and compensate.
 */

`default_nettype none

module serdesphy_ana_cdr (
    // Clock and reset
    input  wire       clk_240m_rx,     // 240 MHz recovered clock
    input  wire       rst_n,           // Active-low reset
    input  wire       cdr_rst,         // CDR reset
    input  wire       enable,          // CDR enable
    
    // Control inputs
    input  wire [2:0] cdr_gain,        // CDR gain setting
    input  wire       cdr_fast_lock,    // Fast acquisition mode
    
    // Data inputs
    input  wire       serial_data,      // Serial data input
    
    // VCO interface
    output wire [7:0] vco_control,     // VCO control voltage
    output wire       cdr_lock,        // CDR lock indicator
    output wire [7:0] phase_detector   // Phase detector output
);

    // =========================================================================
    // Phase Detector (Alexander-style)
    // =========================================================================
    
    reg early_sample, late_sample;
    reg serial_data_prev;
    reg [7:0] phase_detector_reg;
    
    always @(posedge clk_240m_rx or negedge rst_n) begin
        if (!rst_n) begin
            early_sample <= 0;
            late_sample <= 0;
            serial_data_prev <= 0;
        end else if (cdr_rst || !enable) begin
            early_sample <= 0;
            late_sample <= 0;
            serial_data_prev <= 0;
        end else begin
            serial_data_prev <= serial_data;
            early_sample <= serial_data_prev;
            late_sample <= serial_data;
        end
    end
    
    // Phase detector output
    always @(posedge clk_240m_rx or negedge rst_n) begin
        if (!rst_n) begin
            phase_detector_reg <= 8'h80;
        end else if (cdr_rst || !enable) begin
            phase_detector_reg <= 8'h80;
        end else begin
            if (early_sample && !late_sample) begin
                phase_detector_reg <= 8'h80 + {5'b0, cdr_gain};
            end else if (!early_sample && late_sample) begin
                phase_detector_reg <= 8'h80 - {5'b0, cdr_gain};
            end else begin
                phase_detector_reg <= 8'h80;
            end
        end
    end
    
    // =========================================================================
    // Frequency Detector: Accumulate Phase Error Over Window
    // =========================================================================
    
    wire signed [8:0] pd_deviation = $signed({1'b0, phase_detector_reg}) - 9'sd128;
    
    // Accumulate phase error over a 64-cycle window
    localparam [7:0] FREQ_WINDOW = 8'd64;
    reg signed [11:0] phase_accum;
    reg [7:0] freq_window_count;
    reg signed [11:0] freq_error_filtered;
    
    always @(posedge clk_240m_rx or negedge rst_n) begin
        if (!rst_n) begin
            phase_accum <= 12'sd0;
            freq_window_count <= 8'd0;
            freq_error_filtered <= 12'sd0;
        end else if (cdr_rst || !enable) begin
            phase_accum <= 12'sd0;
            freq_window_count <= 8'd0;
            freq_error_filtered <= 12'sd0;
        end else begin
            // Accumulate phase deviation
            phase_accum <= phase_accum + {{3{pd_deviation[8]}}, pd_deviation};
            
            // Every FREQ_WINDOW cycles, capture the accumulated error
            if (freq_window_count >= FREQ_WINDOW - 1) begin
                freq_window_count <= 8'd0;
                freq_error_filtered <= phase_accum;
                phase_accum <= 12'sd0;
            end else begin
                freq_window_count <= freq_window_count + 8'd1;
            end
        end
    end
    
    // =========================================================================
    // PI Loop Filter
    // =========================================================================
    
    reg signed [15:0] freq_integrator;
    reg [7:0] vco_control_reg;
    
    always @(posedge clk_240m_rx or negedge rst_n) begin
        if (!rst_n) begin
            freq_integrator <= 16'sd0;
            vco_control_reg <= 8'h80;
        end else if (cdr_rst || !enable) begin
            freq_integrator <= 16'sd0;
            vco_control_reg <= 8'h80;
        end else begin
            // Integrate frequency error (phase drift over windows)
            // Scale down freq_error_filtered by 32 before integrating
            if (freq_window_count == 8'd0) begin  // Update once per window
                if (freq_integrator < 16'sd8000 && freq_integrator > -16'sd8000) begin
                    freq_integrator <= freq_integrator + (freq_error_filtered >>> 5);
                end
            end
            
            // VCO control depends on lock state
            if (cdr_lock_reg) begin
                // Locked: reduced gain tracking (>>>2) + integral compensation
                vco_control_reg <= $unsigned(
                    $signed({1'b0, phase_detector_reg}) + (pd_deviation >>> 2) + (freq_integrator >>> 6)
                );
            end else begin
                // Acquiring: full proportional + integral
                vco_control_reg <= $unsigned(
                    $signed({1'b0, phase_detector_reg}) + (freq_integrator >>> 6)
                );
            end
        end
    end
    
    // =========================================================================
    // Lock Detector
    // =========================================================================
    
    localparam [8:0]        BALANCE_WINDOW       = 9'd256;
    localparam signed [8:0] BALANCE_THRESHOLD    = 9'sd32;
    localparam [8:0]        MIN_ACTIVITY         = 9'd24;
    localparam [2:0]        CONSECUTIVE_WINDOWS  = 3'd3;
    
    reg signed [8:0] balance_accum;
    reg [8:0]        activity_count;
    reg [8:0]        window_count;
    reg [2:0]        consecutive_balanced;
    reg              cdr_lock_reg;
    
    // Frequency is stable if phase accumulator is small
    wire freq_stable = (freq_error_filtered < 12'sd200) && (freq_error_filtered > -12'sd200);
    
    always @(posedge clk_240m_rx or negedge rst_n) begin
        if (!rst_n) begin
            balance_accum <= 9'sd0;
            activity_count <= 9'd0;
            window_count <= 9'd0;
            consecutive_balanced <= 3'd0;
            cdr_lock_reg <= 1'b0;
        end else if (cdr_rst || !enable) begin
            balance_accum <= 9'sd0;
            activity_count <= 9'd0;
            window_count <= 9'd0;
            consecutive_balanced <= 3'd0;
            cdr_lock_reg <= 1'b0;
        end else begin
            // Accumulate phase detector decisions
            if (phase_detector_reg == (8'h80 + {5'b0, cdr_gain})) begin
                balance_accum <= balance_accum + 9'sd1;
                activity_count <= activity_count + 9'd1;
            end else if (phase_detector_reg == (8'h80 - {5'b0, cdr_gain})) begin
                balance_accum <= balance_accum - 9'sd1;
                activity_count <= activity_count + 9'd1;
            end
            
            // Check balance window
            if (window_count >= BALANCE_WINDOW - 1'b1) begin
                window_count <= 9'd0;
                
                // Balanced if phase is balanced AND frequency is stable
                if ((balance_accum >= -BALANCE_THRESHOLD) &&
                    (balance_accum <= BALANCE_THRESHOLD) &&
                    (activity_count >= MIN_ACTIVITY) &&
                    freq_stable) begin
                    
                    if (consecutive_balanced < CONSECUTIVE_WINDOWS) begin
                        consecutive_balanced <= consecutive_balanced + 1'b1;
                        `ifndef SYNTHESIS
                        $display("[CDR Freq @%0t] Balanced window %0d/%0d (bal=%0d, integrator=%0d, vco=%0d, freq_err=%0d)",
                                 $time, consecutive_balanced + 1'b1, CONSECUTIVE_WINDOWS,
                                 balance_accum, freq_integrator, vco_control_reg, freq_error_filtered);
                        `endif
                    end
                    
                    if (consecutive_balanced >= (CONSECUTIVE_WINDOWS - 1'b1)) begin
                        if (!cdr_lock_reg) begin
                            `ifndef SYNTHESIS
                            $display("[CDR Freq @%0t] LOCK DECLARED (vco=%0d, integrator=%0d)",
                                     $time, vco_control_reg, freq_integrator);
                            `endif
                        end
                        cdr_lock_reg <= 1'b1;
                    end
                end else begin
                    `ifndef SYNTHESIS
                    $display("[CDR Freq @%0t] Unbalanced (bal=%0d, freq_stable=%0b, freq_err=%0d, vco=%0d, int=%0d)",
                             $time, balance_accum, freq_stable, freq_error_filtered, vco_control_reg, freq_integrator);
                    `endif
                    consecutive_balanced <= 3'd0;
                    if (consecutive_balanced == 0) cdr_lock_reg <= 1'b0;
                end
                
                balance_accum <= 9'sd0;
                activity_count <= 9'd0;
            end else begin
                window_count <= window_count + 1'b1;
            end
        end
    end
    
    assign vco_control = vco_control_reg;
    assign cdr_lock = cdr_lock_reg;
    assign phase_detector = phase_detector_reg;

endmodule

`default_nettype wire
