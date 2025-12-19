/*
 * SerDes PHY PLL
 * Ring-oscillator based transmit PLL with 10× multiplication
 * Integrates phase frequency detector, charge pump, loop filter, VCO, and frequency divider
 * 24 MHz input to 240 MHz output
 */

`default_nettype none

module serdesphy_ana_pll (
    // Clock and reset
    input  wire       clk_ref_24m,     // 24 MHz reference clock
    input  wire       rst_n,           // Active-low reset
    input  wire       pll_rst,         // PLL reset
    input  wire       pll_bypass,      // PLL bypass
    input  wire       enable,          // PLL enable
    
    // Control inputs
    input  wire [3:0] vco_trim,        // VCO frequency trim
    input  wire [1:0] cp_current,      // Charge pump current
    
    // Output
    output wire       clk_240m_out,    // 240 MHz output
    output wire       pll_lock,        // PLL lock indicator
    output wire [7:0] vco_control      // VCO control voltage (digital)
);

    // Internal signals
    wire       phase_det_up, phase_det_down;
    wire       charge_pump_out;
    wire [7:0] loop_filter_out;
    wire       vco_out;
    wire       vco_ready;
    wire       divider_output;
    wire       divider_pulse;
    wire       feedback_clk;
    
    // PLL state machine
    reg        pll_lock_reg;
    reg [9:0]  lock_counter;
    reg [1:0]  pll_state;
    
    // State encoding
    localparam STATE_RESET    = 2'b00;
    localparam STATE_ACQUIRE  = 2'b01;
    localparam STATE_TRACK    = 2'b10;
    localparam STATE_LOCKED   = 2'b11;
    
    // Phase Frequency Detector
    serdesphy_ana_phase_frequency_detector u_phase_det (
        .clk_ref        (clk_ref_24m),
        .clk_feedback   (feedback_clk),
        .rst_n          (rst_n && !pll_rst),
        .enable         (enable && !pll_bypass),
        .up_pulse       (phase_det_up),
        .down_pulse     (phase_det_down)
    );
    
    // Charge Pump
    serdesphy_ana_pll_charge_pump u_charge_pump (
        .clk            (clk_ref_24m),
        .rst_n          (rst_n),
        .enable         (enable && !pll_bypass),
        .cp_current     (cp_current),
        .up_pulse       (phase_det_up),
        .down_pulse     (phase_det_down),
        .charge_out     (charge_pump_out)
    );
    
    // Loop Filter
    serdesphy_ana_pll_loop_filter u_loop_filter (
        .clk            (clk_ref_24m),
        .rst_n          (rst_n),
        .enable         (enable && !pll_bypass),
        .charge_in      (charge_pump_out),
        .vco_control     (loop_filter_out)
    );
    
    // VCO
    serdesphy_ana_pll_vco u_vco (
        .rst_n          (rst_n),
        .enable         (enable && !pll_bypass),
        .vco_control    (loop_filter_out | (vco_trim << 4)),  // Apply VCO trim
        .vco_out        (vco_out),
        .vco_ready      (vco_ready)
    );
    
    // Frequency Divider (÷10)
    serdesphy_ana_frequency_divider u_frequency_divider (
        .clk_in         (vco_out),
        .rst_n          (rst_n),
        .enable         (enable && !pll_bypass),
        .clk_out        (divider_output),
        .clk_divided    (divider_pulse)
    );
    
    // Use divided output as feedback to phase detector
    assign feedback_clk = divider_output;
    
    // PLL state machine and lock detection
    always @(posedge clk_ref_24m or negedge rst_n) begin
        if (!rst_n || pll_rst) begin
            pll_state <= STATE_RESET;
            pll_lock_reg <= 0;
            lock_counter <= 10'h000;
        end else if (!enable || pll_bypass) begin
            pll_state <= STATE_RESET;
            pll_lock_reg <= 0;
            lock_counter <= 10'h000;
        end else begin
            case (pll_state)
                STATE_RESET: begin
                    pll_lock_reg <= 0;
                    lock_counter <= 10'h000;
                    if (vco_ready) begin
                        pll_state <= STATE_ACQUIRE;
                    end
                end
                
                STATE_ACQUIRE: begin
                    pll_lock_reg <= 0;
                    lock_counter <= lock_counter + 1;
                    
                    // Check for lock after sufficient time
                    if (lock_counter >= 10'd240) begin  // ~10us at 24MHz
                        pll_state <= STATE_TRACK;
                    end
                end
                
                STATE_TRACK: begin
                    pll_lock_reg <= 1;
                    pll_state <= STATE_LOCKED;
                end
                
                STATE_LOCKED: begin
                    pll_lock_reg <= 1;
                    // Continue tracking - could add loss-of-lock detection here
                end
                
                default: begin
                    pll_state <= STATE_RESET;
                end
            endcase
        end
    end
    
    // Output assignments
    assign clk_240m_out = pll_bypass ? clk_ref_24m : vco_out;
    assign pll_lock = pll_lock_reg && !pll_bypass;
    assign vco_control = loop_filter_out;

endmodule