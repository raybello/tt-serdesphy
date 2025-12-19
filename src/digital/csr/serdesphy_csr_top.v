/*
 * SerDes PHY CSR Top Module
 * Unified CSR interface integrating I2C slave, CSR registers, and debug mux
 * Provides centralized configuration and status monitoring for all PHY blocks
 */

`default_nettype none

module serdesphy_csr_top (
    // Clock and reset
    input  wire       clk,              // System clock (24 MHz)
    input  wire       rst_n,            // Active-low reset
    
    // Physical I2C interface
    inout  wire       sda,              // I2C data (open-drain)
    input  wire       scl,              // I2C clock
    
    // Control outputs to PHY blocks
    output wire       phy_en,           // PHY global enable
    output wire       iso_en,           // Analog isolation enable
    output wire       tx_en,            // Transmit enable
    output wire       tx_fifo_en,       // TX FIFO enable
    output wire       tx_prbs_en,       // TX PRBS enable
    output wire       tx_idle,          // Force idle pattern
    output wire       rx_en,            // Receive enable
    output wire       rx_fifo_en,       // RX FIFO enable
    output wire       rx_prbs_chk_en,   // RX PRBS check enable
    output wire       rx_align_rst,     // Reset alignment FSM
    output wire       tx_data_sel,      // TX data source select
    output wire       rx_data_sel,      // RX output select
    output wire [3:0] vco_trim,         // VCO frequency trim
    output wire [1:0] cp_current,       // Charge pump current
    output wire       pll_rst,          // PLL reset
    output wire       pll_bypass,       // PLL bypass
    output wire [2:0] cdr_gain,         // CDR gain setting
    output wire       cdr_fast_lock,    // CDR fast lock mode
    output wire       cdr_rst,          // CDR reset
    
    // Debug control outputs
    output wire       dbg_vctrl,        // Debug VCO control voltage
    output wire       dbg_pd,           // Debug phase detector
    output wire       dbg_fifo,         // Debug FIFO status
    output wire       dbg_an,           // Analog debug output
    
    // Status inputs from TX block
    input  wire       tx_fifo_full,     // TX FIFO full flag
    input  wire       tx_fifo_empty,    // TX FIFO empty flag
    input  wire       tx_overflow,      // TX FIFO overflow (sticky)
    input  wire       tx_underflow,     // TX FIFO underflow (sticky)
    input  wire       tx_active,        // TX data path active
    input  wire       tx_error,         // TX error flag
    
    // Status inputs from RX block
    input  wire       rx_fifo_full,     // RX FIFO full flag
    input  wire       rx_fifo_empty,    // RX FIFO empty flag
    input  wire       rx_overflow,      // RX FIFO overflow (sticky)
    input  wire       rx_underflow,     // RX FIFO underflow (sticky)
    input  wire       rx_active,        // RX data path active
    input  wire       rx_error,         // RX error flag
    input  wire       rx_aligned,       // RX alignment achieved
    
    // Status inputs from PLL/CDR blocks
    input  wire       pll_lock,         // PLL lock indicator
    input  wire       cdr_lock,         // CDR lock indicator
    input  wire       pll_ready,        // PLL ready flag
    input  wire       phy_ready,        // PHY ready flag
    
    // Status inputs from POR block
    input  wire       power_good,       // Power supplies stable
    input  wire       por_active,       // POR sequence active
    input  wire       por_complete,     // POR sequence complete
    
    // Status inputs from analog blocks
    input  wire       prbs_err,         // PRBS error detected (sticky)
    input  wire [7:0] pll_status,       // Detailed PLL status
    input  wire       pll_error,        // PLL error flag
    
    // Status outputs
    output wire       csr_busy,         // CSR transaction active
    output wire       csr_error,        // CSR transaction error
    output wire [7:0] system_status     // Aggregated system status
);

    // Internal register interface signals
    wire [7:0] reg_addr;
    wire [7:0] reg_wdata;
    wire       reg_write_en;
    wire [7:0] reg_rdata;
    wire       reg_read_en;
    
    // I2C interface status
    wire i2c_busy;
    wire i2c_error;
    
    // Status aggregation
    wire fifo_err;
    wire system_error;
    
    // Instantiate I2C slave interface
    serdesphy_i2c_slave u_i2c_slave (
        .clk          (clk),
        .rst_n        (rst_n),
        .sda          (sda),
        .scl          (scl),
        .reg_addr     (reg_addr),
        .reg_wdata    (reg_wdata),
        .reg_write_en (reg_write_en),
        .reg_rdata    (reg_rdata),
        .reg_read_en  (reg_read_en),
        .i2c_busy     (i2c_busy),
        .i2c_error    (i2c_error)
    );
    
    // FIFO error aggregation
    assign fifo_err = tx_overflow || tx_underflow || rx_overflow || rx_underflow;
    
    // Instantiate CSR registers with enhanced status
    serdesphy_csr_registers u_csr_registers (
        .clk             (clk),
        .rst_n           (rst_n),
        .reg_addr        (reg_addr),
        .reg_wdata       (reg_wdata),
        .reg_write_en    (reg_write_en),
        .reg_rdata       (reg_rdata),
        .reg_read_en     (reg_read_en),
        
        // Control outputs
        .phy_en          (phy_en),
        .iso_en          (iso_en),
        .tx_en           (tx_en),
        .tx_fifo_en      (tx_fifo_en),
        .tx_prbs_en      (tx_prbs_en),
        .tx_idle         (tx_idle),
        .rx_en           (rx_en),
        .rx_fifo_en      (rx_fifo_en),
        .rx_prbs_chk_en  (rx_prbs_chk_en),
        .rx_align_rst    (rx_align_rst),
        .tx_data_sel     (tx_data_sel),
        .rx_data_sel     (rx_data_sel),
        .vco_trim        (vco_trim),
        .cp_current      (cp_current),
        .pll_rst         (pll_rst),
        .pll_bypass      (pll_bypass),
        .cdr_gain        (cdr_gain),
        .cdr_fast_lock   (cdr_fast_lock),
        .cdr_rst         (cdr_rst),
        .dbg_vctrl       (dbg_vctrl),
        .dbg_pd          (dbg_pd),
        .dbg_fifo        (dbg_fifo),
        
        // Status inputs (from original specification)
        .pll_lock        (pll_lock),
        .cdr_lock        (cdr_lock),
        .tx_fifo_full    (tx_fifo_full),
        .tx_fifo_empty   (tx_fifo_empty),
        .rx_fifo_full    (rx_fifo_full),
        .rx_fifo_empty   (rx_fifo_empty),
        .prbs_err        (prbs_err),
        .fifo_err        (fifo_err)
    );
    
    // Debug input multiplexing
    wire [7:0] debug_sources;
    assign debug_sources = {
        pll_status[7:0],     // Source 7: Detailed PLL status
        1'b0,               // Source 6: Reserved
        1'b0,               // Source 5: Reserved
        1'b0,               // Source 4: Reserved
        tx_fifo_full,        // Source 3: TX FIFO full
        rx_fifo_full,        // Source 2: RX FIFO full
        pll_lock,            // Source 1: PLL lock
        cdr_lock             // Source 0: CDR lock
    };
    
    // Instantiate debug mux
    serdesphy_debug_mux u_debug_mux (
        .clk           (clk),
        .rst_n         (rst_n),
        
        // Debug selection control
        .dbg_vctrl     (dbg_vctrl),
        .dbg_pd        (dbg_pd),
        .dbg_fifo      (dbg_fifo),
        
        // Debug input sources
        .debug_sources (debug_sources),
        
        // Analog debug output
        .debug_analog  (dbg_an)
    );
    
    // System status aggregation
    assign system_error = fifo_err || prbs_err || pll_error || tx_error || rx_error || i2c_error;
    
    assign system_status = {
        system_error,       // Bit 7: Any system error
        por_active,         // Bit 6: POR sequence active
        por_complete,       // Bit 5: POR sequence complete
        phy_ready,          // Bit 4: PHY ready for operation
        pll_ready,          // Bit 3: PLL ready
        rx_aligned,         // Bit 2: RX alignment achieved
        tx_active && rx_active, // Bit 1: Both TX and RX active
        power_good          // Bit 0: Power supplies good
    };
    
    // CSR status outputs
    assign csr_busy = i2c_busy;
    assign csr_error = i2c_error || system_error;

endmodule