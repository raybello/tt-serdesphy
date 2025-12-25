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
    
    // Control outputs to PHY blocks (from CSR registers)
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
    
    // Status inputs from PHY blocks (for STATUS register 0x06)
    input        tx_fifo_full,     // TX FIFO full flag
    input        tx_fifo_empty,    // TX FIFO empty flag
    input        tx_overflow,      // TX FIFO overflow (sticky)
    input        tx_underflow,     // TX FIFO underflow (sticky)
    input        rx_fifo_full,     // RX FIFO full flag
    input        rx_fifo_empty,    // RX FIFO empty flag
    input        rx_overflow,      // RX FIFO overflow (sticky)
    input        rx_underflow,     // RX FIFO underflow (sticky)
    input        pll_lock,         // PLL lock indicator
    input        cdr_lock,         // CDR lock indicator
    input        prbs_err          // PRBS error detected (sticky)
);

    // Register bank definitions (8 registers, 8 bits each)
    localparam NUM_REGS = 8;
    localparam REG_WIDTH = 8;
    
    // Register interface signals
    wire [NUM_REGS*REG_WIDTH-1:0] regs_out;  // Registers written by I2C
    wire [NUM_REGS*REG_WIDTH-1:0] regs_in;   // Registers read by I2C
    wire reg_write_strobe;
    wire [7:0] reg_addr_i2c;
    
    // I2C interface status
    wire [7:0] i2c_status;
    wire i2c_error;
    
    // Status aggregation
    wire fifo_err;
    wire system_error;
    
    // Individual register wires for readability
    wire [7:0] phy_enable_reg;      // 0x00
    wire [7:0] tx_config_reg;       // 0x01
    wire [7:0] rx_config_reg;       // 0x02
    wire [7:0] data_select_reg;     // 0x03
    wire [7:0] pll_config_reg;      // 0x04
    wire [7:0] cdr_config_reg;      // 0x05
    wire [7:0] status_reg;          // 0x06 (read-only)
    wire [7:0] debug_enable_reg;    // 0x07
    
    // Extract registers from regs_out (written by I2C)
    assign phy_enable_reg    = regs_out[0*8 +: 8];
    assign tx_config_reg     = regs_out[1*8 +: 8];
    assign rx_config_reg     = regs_out[2*8 +: 8];
    assign data_select_reg   = regs_out[3*8 +: 8];
    assign pll_config_reg    = regs_out[4*8 +: 8];
    assign cdr_config_reg    = regs_out[5*8 +: 8];
    assign debug_enable_reg  = regs_out[7*8 +: 8];
    
    // Instantiate I2C slave interface
    i2c_slave #(
        .DEVICE_ADDR(7'h42),
        .NUM_REGS(NUM_REGS),
        .REG_WIDTH(REG_WIDTH)
    ) u_i2c_slave (
        .clk               (clk),
        .rst_n             (rst_n),
        .scl_in            (scl),
        .sda_io            (sda),
        .regs_out          (regs_out),
        .regs_in           (regs_in),
        .reg_write_strobe  (reg_write_strobe),
        .reg_addr          (reg_addr_i2c),
        .status            (i2c_status),
        .bus_error         (i2c_error)
    );
    
    // FIFO error aggregation
    assign fifo_err = tx_overflow || tx_underflow || rx_overflow || rx_underflow;
    
    //========================================
    // Register Mapping to Control Signals
    //========================================
    
    // PHY_ENABLE (0x00)
    assign phy_en  = phy_enable_reg[0];
    assign iso_en  = phy_enable_reg[1];
    
    // TX_CONFIG (0x01)
    assign tx_en       = tx_config_reg[0];
    assign tx_fifo_en  = tx_config_reg[1];
    assign tx_prbs_en  = tx_config_reg[2];
    assign tx_idle     = tx_config_reg[3];
    
    // RX_CONFIG (0x02)
    assign rx_en           = rx_config_reg[0];
    assign rx_fifo_en      = rx_config_reg[1];
    assign rx_prbs_chk_en  = rx_config_reg[2];
    assign rx_align_rst    = rx_config_reg[3];
    
    // DATA_SELECT (0x03)
    assign tx_data_sel = data_select_reg[0];
    assign rx_data_sel = data_select_reg[1];
    
    // PLL_CONFIG (0x04)
    assign vco_trim    = pll_config_reg[3:0];
    assign cp_current  = pll_config_reg[5:4];
    assign pll_rst     = pll_config_reg[6];
    assign pll_bypass  = pll_config_reg[7];
    
    // CDR_CONFIG (0x05)
    assign cdr_gain      = cdr_config_reg[2:0];
    assign cdr_fast_lock = cdr_config_reg[3];
    assign cdr_rst       = cdr_config_reg[4];
    
    // DEBUG_ENABLE (0x07)
    assign dbg_vctrl = debug_enable_reg[0];
    assign dbg_pd    = debug_enable_reg[1];
    assign dbg_fifo  = debug_enable_reg[2];
    
    //========================================
    // Status Register Building (0x06 - Read Only)
    //========================================
    assign status_reg = {
        fifo_err,           // Bit 7: FIFO overflow/underflow
        prbs_err,           // Bit 6: PRBS error detected
        rx_fifo_empty,      // Bit 5: RX FIFO empty
        rx_fifo_full,       // Bit 4: RX FIFO full
        tx_fifo_empty,      // Bit 3: TX FIFO empty
        tx_fifo_full,       // Bit 2: TX FIFO full
        cdr_lock,           // Bit 1: CDR lock indicator
        pll_lock            // Bit 0: PLL lock indicator
    };
    
    //========================================
    // Register Input Array (regs_in)
    //========================================
    // Build the input register array for I2C reads
    // Writeable registers echo back their values, status register shows status
    assign regs_in = {
        debug_enable_reg,   // 0x07
        status_reg,         // 0x06 (read-only)
        cdr_config_reg,     // 0x05
        pll_config_reg,     // 0x04
        data_select_reg,    // 0x03
        rx_config_reg,      // 0x02
        tx_config_reg,      // 0x01
        phy_enable_reg      // 0x00
    };
    
    // Debug analog output (placeholder - to be connected to actual debug mux)
    assign dbg_an = 1'b0;

endmodule