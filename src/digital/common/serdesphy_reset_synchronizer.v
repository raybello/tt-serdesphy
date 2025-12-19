/*
 * SerDes PHY Reset Synchronizer
 * Reset synchronization across clock domains
 * Provides clean, synchronized resets to all modules
 */

`default_nettype none

module serdesphy_reset_synchronizer (
    // Primary clock and reset
    input  wire       clk_ref_24m,     // 24 MHz reference clock
    input  wire       rst_n_in,         // External async reset
    
    // Clock domains to synchronize to
    input  wire       clk_240m_tx,     // 240 MHz TX clock
    input  wire       clk_240m_rx,     // 240 MHz RX clock
    
    // Control inputs
    input  wire       phy_en,          // PHY enable
    input  wire       pll_rst,         // PLL reset
    input  wire       cdr_rst,         // CDR reset
    
    // Synchronized reset outputs
    output wire       rst_n_24m,       // Synchronized 24MHz reset
    output wire       rst_n_240m_tx,   // Synchronized 240MHz TX reset
    output wire       rst_n_240m_rx,   // Synchronized 240MHz RX reset
    output wire       pll_rst_sync,     // Synchronized PLL reset
    output wire       cdr_rst_sync      // Synchronized CDR reset
);

    // Internal reset generation
    wire       master_reset_n;    // Master synchronized reset
    reg        rst_24m_sync1, rst_24m_sync2;
    reg        rst_240m_tx_sync1, rst_240m_tx_sync2;
    reg        rst_240m_rx_sync1, rst_240m_rx_sync2;
    reg        pll_rst_sync1, pll_rst_sync2;
    reg        cdr_rst_sync1, cdr_rst_sync2;
    
    // Master reset synchronization (to 24MHz domain)
    always @(posedge clk_ref_24m or negedge rst_n_in) begin
        if (!rst_n_in) begin
            rst_24m_sync1 <= 1'b1;   // Reset active
            rst_24m_sync2 <= 1'b1;
        end else begin
            rst_24m_sync1 <= 1'b0;   // Reset released
            rst_24m_sync2 <= rst_24m_sync1;
        end
    end
    
    // Generate master reset (consider PHY enable)
    assign master_reset_n = rst_24m_sync2 && phy_en;
    
    // Synchronize reset to 240MHz TX clock domain
    always @(posedge clk_240m_tx or negedge master_reset_n) begin
        if (!master_reset_n) begin
            rst_240m_tx_sync1 <= 1'b1;  // Reset active
            rst_240m_tx_sync2 <= 1'b1;
        end else begin
            rst_240m_tx_sync1 <= 1'b0;   // Reset released
            rst_240m_tx_sync2 <= rst_240m_tx_sync1;
        end
    end
    
    // Synchronize reset to 240MHz RX clock domain
    always @(posedge clk_240m_rx or negedge master_reset_n) begin
        if (!master_reset_n) begin
            rst_240m_rx_sync1 <= 1'b1;  // Reset active
            rst_240m_rx_sync2 <= 1'b1;
        end else begin
            rst_240m_rx_sync1 <= 1'b0;   // Reset released
            rst_240m_rx_sync2 <= rst_240m_rx_sync1;
        end
    end
    
    // Synchronize PLL reset (to 24MHz domain)
    always @(posedge clk_ref_24m or negedge rst_n_in) begin
        if (!rst_n_in) begin
            pll_rst_sync1 <= 1'b0;  // PLL reset inactive
            pll_rst_sync2 <= 1'b0;
        end else begin
            pll_rst_sync1 <= pll_rst;
            pll_rst_sync2 <= pll_rst_sync1;
        end
    end
    
    // Synchronize CDR reset (to 24MHz domain)
    always @(posedge clk_ref_24m or negedge rst_n_in) begin
        if (!rst_n_in) begin
            cdr_rst_sync1 <= 1'b0;  // CDR reset inactive
            cdr_rst_sync2 <= 1'b0;
        end else begin
            cdr_rst_sync1 <= cdr_rst;
            cdr_rst_sync2 <= cdr_rst_sync1;
        end
    end
    
    // Output assignments
    assign rst_n_24m = master_reset_n;
    assign rst_n_240m_tx = rst_240m_tx_sync2;
    assign rst_n_240m_rx = rst_240m_rx_sync2;
    assign pll_rst_sync = pll_rst_sync2;
    assign cdr_rst_sync = cdr_rst_sync2;

endmodule