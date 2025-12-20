/*
 * SerDes PHY PLL Controller
 * Extends clock_manager with dedicated PLL configuration and monitoring
 * Manages VCO trim, charge pump control, and enhanced lock detection
 */

`default_nettype none

module serdesphy_pll_ctrl (
    // Clock and reset
    input  wire       clk_ref_24m,     // 24 MHz reference clock
    input  wire       rst_n,           // Active-low reset
    
    // Control inputs from CSR
    input  wire       phy_en,          // PHY global enable
    input  wire [3:0] vco_trim,        // VCO frequency coarse trim
    input  wire [1:0] cp_current,      // Charge pump current select
    input  wire       pll_rst,         // PLL reset
    input  wire       pll_bypass,       // PLL bypass mode
    
    // Clock enables and status to analog PLL
    output wire       pll_enable,      // PLL enable
    output wire       pll_reset_n,     // PLL reset (active-low)
    output wire       pll_bypass_en,   // PLL bypass enable
    output wire [3:0] pll_vco_trim,    // VCO trim control
    output wire [1:0] pll_cp_current,  // Charge pump current control
    output wire       pll_iso_n,       // PLL isolation control
    
    // Status from analog PLL
    input  wire       pll_lock_raw,    // Raw PLL lock from analog
    input  wire       pll_vco_ok,      // VCO operating range indicator
    input  wire       pll_cp_ok,       // Charge pump OK indicator
    
    // Enhanced status outputs
    output wire       pll_lock,        // Validated PLL lock
    output wire       pll_ready,       // PLL ready for operation
    output wire [7:0] pll_status,      // Detailed PLL status
    output wire       pll_error,       // PLL error flag
    
    // Clock management outputs
    output wire       clk_24m_en,      // 24 MHz clock enable
    output wire       clk_240m_tx_en,  // 240 MHz TX clock enable
    output wire       clk_240m_rx_en,  // 240 MHz RX clock enable
    output wire       cdr_lock,        // CDR lock indicator
    output wire       phy_ready        // PHY ready for operation
);

    // Enhanced lock detection parameters
    localparam LOCK_COUNT_MAX = 16'd2400;  // 100us at 24MHz for robust detection
    localparam LOCK_COUNT_MIN = 16'd240;   // 10us minimum for lock claim
    localparam UNLOCK_COUNT   = 16'd240;   // 10us before unlock declaration
    
    // PLL status register bits
    localparam STATUS_PLL_EN       = 7;
    localparam STATUS_PLL_BYPASS   = 6;
    localparam STATUS_VCO_TRIM     = 5'h2;
    localparam STATUS_CP_CURRENT   = 1'h0;
    
    // Internal signals
    reg        pll_enable_reg;
    reg        pll_reset_n_reg;
    reg        pll_bypass_en_reg;
    reg [3:0]  pll_vco_trim_reg;
    reg [1:0]  pll_cp_current_reg;
    reg        pll_iso_n_reg;
    reg        pll_lock_reg;
    reg        pll_ready_reg;
    reg        pll_error_reg;
    reg [15:0] lock_counter;
    reg [15:0] unlock_counter;
    reg [7:0]  pll_status_reg;
    
    // Lock detection state machine
    localparam [1:0]
        LOCK_STATE_UNLOCKED  = 2'b00,
        LOCK_STATE_ACQUIRING = 2'b01,
        LOCK_STATE_LOCKED    = 2'b10,
        LOCK_STATE_ERROR     = 2'b11;
    
    reg [1:0] lock_state;
    
    // Instantiate existing clock manager
    wire base_clk_24m_en;
    wire base_clk_240m_tx_en;
    wire base_clk_240m_rx_en;
    wire base_pll_lock;
    wire base_cdr_lock;
    wire base_phy_ready;
    
    serdesphy_clock_manager u_clock_manager (
        .clk_ref_24m     (clk_ref_24m),
        .rst_n           (rst_n),
        .phy_en          (phy_en),
        .pll_rst         (pll_rst),
        .cdr_rst         (1'b0),        // CDR reset handled elsewhere
        .clk_24m_en      (base_clk_24m_en),
        .clk_240m_tx_en  (base_clk_240m_tx_en),
        .clk_240m_rx_en  (base_clk_240m_rx_en),
        .pll_lock        (base_pll_lock),
        .cdr_lock        (base_cdr_lock),
        .phy_ready       (base_phy_ready)
    );
    
    // Enhanced PLL control logic
    always @(posedge clk_ref_24m or negedge rst_n) begin
        if (!rst_n) begin
            pll_enable_reg <= 1'b0;
            pll_reset_n_reg <= 1'b0;
            pll_bypass_en_reg <= 1'b0;
            pll_vco_trim_reg <= 4'h8;    // Default nominal frequency
            pll_cp_current_reg <= 2'h2;  // Default 40µA
            pll_iso_n_reg <= 1'b1;       // Start with isolation disabled
        end else begin
            // PLL enable control
            pll_enable_reg <= phy_en && !pll_rst;
            
            // PLL reset control (active-low reset to analog)
            pll_reset_n_reg <= !pll_rst && phy_en;
            
            // PLL bypass control
            pll_bypass_en_reg <= pll_bypass && phy_en;
            
            // VCO trim control
            if (pll_enable_reg && !pll_bypass_en_reg) begin
                pll_vco_trim_reg <= vco_trim;
            end
            
            // Charge pump current control
            pll_cp_current_reg <= cp_current;
            
            // PLL isolation control (enable isolation during reset/bypass)
            pll_iso_n_reg <= !(pll_rst || !phy_en || pll_bypass_en_reg);
        end
    end
    
    // Enhanced lock detection with validation
    always @(posedge clk_ref_24m or negedge rst_n) begin
        if (!rst_n) begin
            lock_state <= LOCK_STATE_UNLOCKED;
            lock_counter <= 16'd0;
            unlock_counter <= 16'd0;
            pll_lock_reg <= 1'b0;
            pll_ready_reg <= 1'b0;
            pll_error_reg <= 1'b0;
        end else begin
            case (lock_state)
                LOCK_STATE_UNLOCKED: begin
                    if (pll_enable_reg && !pll_bypass_en_reg && 
                        pll_lock_raw && pll_vco_ok && pll_cp_ok) begin
                        lock_state <= LOCK_STATE_ACQUIRING;
                        lock_counter <= 16'd0;
                        unlock_counter <= 16'd0;
                    end else if (pll_enable_reg && !pll_bypass_en_reg && 
                               (!pll_vco_ok || !pll_cp_ok)) begin
                        lock_state <= LOCK_STATE_ERROR;
                        pll_error_reg <= 1'b1;
                    end
                end
                
                LOCK_STATE_ACQUIRING: begin
                    if (pll_lock_raw && pll_vco_ok && pll_cp_ok) begin
                        if (lock_counter < LOCK_COUNT_MAX) begin
                            lock_counter <= lock_counter + 1;
                        end else begin
                            lock_state <= LOCK_STATE_LOCKED;
                            pll_lock_reg <= 1'b1;
                            pll_ready_reg <= 1'b1;
                        end
                    end else begin
                        lock_state <= LOCK_STATE_UNLOCKED;
                        lock_counter <= 16'd0;
                        unlock_counter <= 16'd0;
                    end
                end
                
                LOCK_STATE_LOCKED: begin
                    if (!pll_enable_reg || pll_bypass_en_reg) begin
                        lock_state <= LOCK_STATE_UNLOCKED;
                        pll_lock_reg <= 1'b0;
                        pll_ready_reg <= 1'b0;
                    end else if (!pll_lock_raw || !pll_vco_ok || !pll_cp_ok) begin
                        if (unlock_counter < UNLOCK_COUNT) begin
                            unlock_counter <= unlock_counter + 1;
                        end else begin
                            lock_state <= LOCK_STATE_UNLOCKED;
                            pll_lock_reg <= 1'b0;
                            pll_ready_reg <= 1'b0;
                            unlock_counter <= 16'd0;
                        end
                    end else begin
                        unlock_counter <= 16'd0;  // Reset unlock counter
                    end
                end
                
                LOCK_STATE_ERROR: begin
                    if (!pll_enable_reg) begin
                        lock_state <= LOCK_STATE_UNLOCKED;
                        pll_error_reg <= 1'b0;
                    end
                end
                
                default: begin
                    lock_state <= LOCK_STATE_ERROR;
                    pll_error_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // PLL status register construction
    always @(posedge clk_ref_24m or negedge rst_n) begin
        if (!rst_n) begin
            pll_status_reg <= 8'h00;
        end else begin
            pll_status_reg <= {
                pll_enable_reg,           // Bit 7: PLL enabled
                pll_bypass_en_reg,         // Bit 6: PLL bypass
                pll_vco_trim_reg,          // Bits 5:2: VCO trim
                pll_cp_current_reg        // Bits 1:0: Charge pump current
            };
        end
    end
    
    // Output assignments
    assign pll_enable = pll_enable_reg;
    assign pll_reset_n = pll_reset_n_reg;
    assign pll_bypass_en = pll_bypass_en_reg;
    assign pll_vco_trim = pll_vco_trim_reg;
    assign pll_cp_current = pll_cp_current_reg;
    assign pll_iso_n = pll_iso_n_reg;
    assign pll_lock = pll_lock_reg;
    assign pll_ready = pll_ready_reg;
    assign pll_error = pll_error_reg;
    assign pll_status = pll_status_reg;
    
    // Use enhanced outputs or fall back to base clock manager
    assign clk_24m_en = pll_enable_reg ? base_clk_24m_en : 1'b0;
    assign clk_240m_tx_en = pll_ready_reg ? base_clk_240m_tx_en : 1'b0;
    assign clk_240m_rx_en = pll_ready_reg ? base_clk_240m_rx_en : 1'b0;
    assign cdr_lock = base_cdr_lock;
    assign phy_ready = pll_ready_reg && base_phy_ready;

endmodule