/*
 * SerDes PHY Frequency Divider
 * Counter-based divide-by-10 with a 50% duty-cycle output.
 *
 * The explicit initial values are needed because the divider is clocked by the
 * VCO, which starts only after rst_n has already been released. Without them,
 * simulators that leave regs at X (Icarus) never recover a defined counter.
 */

`default_nettype none
`timescale 1ns / 1ps

module serdesphy_ana_frequency_divider (
    input  wire       clk_in,         // VCO output
    input  wire       rst_n,
    input  wire       enable,

    output wire       clk_out,        // Divided clock (50% duty)
    output wire       clk_divided     // One-cycle pulse at the terminal count
);

    reg [3:0] counter;
    reg       clk_divided_reg;
    reg       clk_out_reg;

    initial begin
        counter         = 4'h0;
        clk_divided_reg = 1'b0;
        clk_out_reg     = 1'b0;
    end

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            counter         <= 4'h0;
            clk_divided_reg <= 1'b0;
        end else if (!enable) begin
            counter         <= 4'h0;
            clk_divided_reg <= 1'b0;
        end else if (counter == 4'h9) begin
            counter         <= 4'h0;
            clk_divided_reg <= 1'b1;
        end else begin
            counter         <= counter + 1;
            clk_divided_reg <= 1'b0;
        end
    end

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            clk_out_reg <= 1'b0;
        end else if (!enable) begin
            clk_out_reg <= 1'b0;
        end else if (counter == 4'h9 || counter == 4'h4) begin
            clk_out_reg <= ~clk_out_reg;
        end
    end

    assign clk_out     = clk_out_reg;
    assign clk_divided = clk_divided_reg;

endmodule

`default_nettype wire
