/*
 * SerDes PHY Frequency Divider
 * Simple counter-based ÷10 frequency divider
 * Converts 240 MHz to 24 MHz for PLL feedback
 */

`default_nettype none

module serdesphy_ana_frequency_divider (
    // Clock and reset
    input  wire       clk_in,         // 240 MHz input from VCO
    input  wire       rst_n,          // Active-low reset
    input  wire       enable,         // Enable divider
    
    // Output
    output wire       clk_out,        // 24 MHz output (÷10)
    output wire       clk_divided     // Divided clock output
);

    // Internal registers
    reg [3:0]  counter;         // 4-bit counter (0-9)
    reg        clk_divided_reg;
    
    // Counter-based ÷10 divider
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 4'h0;
            clk_divided_reg <= 1'b0;
        end else if (!enable) begin
            counter <= 4'h0;
            clk_divided_reg <= 1'b0;
        end else begin
            if (counter == 4'h9) begin
                counter <= 4'h0;
                clk_divided_reg <= 1'b1;
            end else begin
                counter <= counter + 1;
                clk_divided_reg <= 1'b0;
            end
        end
    end
    
    // Generate divided clock with 50% duty cycle (registered to avoid glitches)
    reg clk_out_reg;
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            clk_out_reg <= 1'b0;
        end else if (!enable) begin
            clk_out_reg <= 1'b0;
        end else begin
            // Toggle on terminal count for 50% duty cycle
            if (counter == 4'h9 || counter == 4'h4) begin
                clk_out_reg <= ~clk_out_reg;
            end
        end
    end

    // Output assignments
    assign clk_out = clk_out_reg;
    assign clk_divided = clk_divided_reg;

endmodule