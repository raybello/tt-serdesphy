/*
 * SerDes PHY CSR Top Module
 * Unified CSR interface integrating I2C slave, CSR registers, and debug mux
 * Provides centralized configuration and status monitoring for all PHY blocks
 */

`default_nettype none

module serdesphy_csr_top (
    // Clock and reset
    input       clk,              // System clock (24 MHz)
    input       rst_n,            // Active-low reset
    
    // Physical I2C interface
    inout       sda,              // I2C data (open-drain)
    input       scl,              // I2C clock
    
    // Control outputs to PHY blocks
    output       phy_en,           // PHY global enable
    output       iso_en,           // Analog isolation enable
    output       tx_en,            // Transmit enable
    output       tx_fifo_en,       // TX FIFO enable
    output       tx_prbs_en,       // TX PRBS enable
    output       tx_idle,          // Force idle pattern
    output       rx_en,            // Receive enable
    output       rx_fifo_en,       // RX FIFO enable
    output       rx_prbs_chk_en,   // RX PRBS check enable
    output       rx_align_rst,     // Reset alignment FSM
    output       tx_data_sel,      // TX data source select
    output       rx_data_sel,      // RX output select
    output [3:0] vco_trim,         // VCO frequency trim
    output [1:0] cp_current,       // Charge pump current
    output       pll_rst,          // PLL reset
    output       pll_bypass,       // PLL bypass
    output [2:0] cdr_gain,         // CDR gain setting
    output       cdr_fast_lock,    // CDR fast lock mode
    output       cdr_rst,          // CDR reset
    
    // Debug control outputs
    output       dbg_vctrl,        // Debug VCO control voltage
    output       dbg_pd,           // Debug phase detector
    output       dbg_fifo,         // Debug FIFO status
    output       dbg_an,           // Analog debug output
    
    // Status inputs from TX block
    input        tx_fifo_full,     // TX FIFO full flag
    input        tx_fifo_empty,    // TX FIFO empty flag
    input        tx_overflow,      // TX FIFO overflow (sticky)
    input        tx_underflow,     // TX FIFO underflow (sticky)
    input        tx_active,        // TX data path active
    input        tx_error,         // TX error flag
    
    // Status inputs from RX block
    input        rx_fifo_full,     // RX FIFO full flag
    input        rx_fifo_empty,    // RX FIFO empty flag
    input        rx_overflow,      // RX FIFO overflow (sticky)
    input        rx_underflow,     // RX FIFO underflow (sticky)
    input        rx_active,        // RX data path active
    input        rx_error,         // RX error flag
    input        rx_aligned,       // RX alignment achieved
    
    // Status inputs from PLL/CDR blocks
    input        pll_lock,         // PLL lock indicator
    input        cdr_lock,         // CDR lock indicator
    input        pll_ready,        // PLL ready flag
    input        phy_ready,        // PHY ready flag
    
    // Status inputs from POR block
    input        power_good,       // Power supplies stable
    input        por_active,       // POR sequence active
    input        por_complete,     // POR sequence complete
    
    // Status inputs from analog blocks
    input        prbs_err,         // PRBS error detected (sticky)
    input  [7:0] pll_status,       // Detailed PLL status
    input        pll_error,        // PLL error flag
    
    // Status outputs
    output       csr_busy,         // CSR transaction active
    output       csr_error,        // CSR transaction error
    output [7:0] system_status     // Aggregated system status
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
    // serdesphy_i2c_slave u_i2c_slave (
    //     .clk          (clk),
    //     .rst_n        (rst_n),
    //     .sda          (sda),
    //     .scl          (scl),
    //     .reg_addr     (reg_addr),
    //     .reg_wdata    (reg_wdata),
    //     .reg_write_en (reg_write_en),
    //     .reg_rdata    (reg_rdata),
    //     .reg_read_en  (reg_read_en),
    //     .i2c_busy     (i2c_busy),
    //     .i2c_error    (i2c_error)
    // );
    
    // FIFO error aggregation
    assign fifo_err = tx_overflow || tx_underflow || rx_overflow || rx_underflow;
    
    
    // Debug signals
    wire [7:0] debug_analog_internal;
    
    // Instantiate debug mux
    // serdesphy_debug_mux u_debug_mux (
    //     .clk           (clk),
    //     .rst_n         (rst_n),
        
    //     // Debug selection control
    //     .dbg_vctrl     (dbg_vctrl),
    //     .dbg_pd        (dbg_pd),
    //     .dbg_fifo      (dbg_fifo),
        
    //     // Debug input signals (using available status)
    //     .vco_control   (pll_status),     // Use PLL status as VCO control representation
    //     .phase_detector({6'b000000, cdr_lock, pll_lock}), // Create 8-bit phase detector status
    //     .fifo_status   ({tx_fifo_full, tx_fifo_empty, rx_fifo_full, rx_fifo_empty, 4'b0000}), // FIFO status bits
        
    //     // Analog debug output
    //     .debug_analog  (debug_analog_internal)
        
    // );
    
    // Use only bit 0 of debug output for 1-bit interface  
    assign dbg_an = debug_analog_internal[0];
    
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