/*
 * SerDes PHY Phase Frequency Detector
 * Simple phase frequency detector with UP/DOWN outputs
 * Compatible with charge pump interface
 */

`default_nettype none

module serdesphy_ana_phase_frequency_detector (
    // Clock inputs
    input  wire       clk_ref,        // 24 MHz reference clock
    input  wire       clk_feedback,    // 24 MHz feedback from ÷10 divider
    input  wire       rst_n,          // Active-low reset
    input  wire       enable,         // Enable PFD
    
    // Phase detector outputs
    output wire       up_pulse,       // UP pulse for charge pump
    output wire       down_pulse      // DOWN pulse for charge pump
);

    // Internal registers
    reg        ref_d1, ref_d2;
    reg        fb_d1, fb_d2;
    reg        up_reg, down_reg;
    
    // Edge detection for reference clock
    always @(posedge clk_ref or negedge rst_n) begin
        if (!rst_n) begin
            ref_d1 <= 1'b0;
            ref_d2 <= 1'b0;
        end else begin
            ref_d2 <= ref_d1;
            ref_d1 <= 1'b1;
        end
    end
    
    // Edge detection for feedback clock
    always @(posedge clk_feedback or negedge rst_n) begin
        if (!rst_n) begin
            fb_d1 <= 1'b0;
            fb_d2 <= 1'b0;
        end else begin
            fb_d2 <= fb_d1;
            fb_d1 <= 1'b1;
        end
    end
    
    // Phase frequency detector logic
    always @(*) begin
        if (!enable) begin
            up_reg = 1'b0;
            down_reg = 1'b0;
        end else begin
            // Simple phase detector logic
            // If reference leads feedback, generate UP pulse
            // If feedback leads reference, generate DOWN pulse
            
            if (ref_d1 && !ref_d2) begin  // Reference rising edge
                if (fb_d1) begin
                    down_reg = 1'b1;  // Feedback already high - slow down
                    up_reg = 1'b0;
                end else begin
                    up_reg = 1'b1;    // Feedback still low - speed up
                    down_reg = 1'b0;
                end
            end else if (fb_d1 && !fb_d2) begin  // Feedback rising edge
                if (ref_d1) begin
                    up_reg = 1'b1;    // Reference already high - speed up
                    down_reg = 1'b0;
                end else begin
                    down_reg = 1'b1;  // Reference still low - slow down
                    up_reg = 1'b0;
                end
            end else begin
                up_reg = 1'b0;
                down_reg = 1'b0;
            end
        end
    end
    
    // Output assignments
    assign up_pulse = up_reg;
    assign down_pulse = down_reg;

endmodule