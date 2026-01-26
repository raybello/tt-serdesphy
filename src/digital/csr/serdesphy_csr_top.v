/*
 * SerDes PHY CSR Top Module
 * Unified CSR interface integrating I2C slave, CSR registers, and debug mux
 * Provides centralized configuration and status monitoring for all PHY blocks
 *
 * Based on OpenCore I2C Slave implementation
 */

`default_nettype none
`timescale 1ns / 1ps

module serdesphy_csr_top (
    // Clock and reset
    input  wire        clk,              // System clock (24 MHz)
    input  wire        rst_n,            // Active-low reset

    // Physical I2C interface - separate signals for Tiny Tapeout IO
    input  wire        sda_in,           // SDA input from IO pad
    output wire        sda_out,          // SDA output to IO pad
    output wire        sda_oe,           // SDA output enable (active high)
    input  wire        scl,              // I2C clock

    // Control outputs to PHY blocks (from CSR registers)
    output wire        phy_en,           // PHY global enable
    output wire        iso_en,           // Analog isolation enable
    output wire        tx_en,            // Transmit enable
    output wire        tx_fifo_en,       // TX FIFO enable
    output wire        tx_prbs_en,       // TX PRBS enable
    output wire        tx_idle,          // Force idle pattern
    output wire        rx_en,            // Receive enable
    output wire        rx_fifo_en,       // RX FIFO enable
    output wire        rx_prbs_chk_en,   // RX PRBS check enable
    output wire        rx_align_rst,     // Reset alignment FSM
    output wire        tx_data_sel,      // TX data source select
    output wire        rx_data_sel,      // RX output select
    output wire [3:0]  vco_trim,         // VCO frequency trim
    output wire [1:0]  cp_current,       // Charge pump current
    output wire        pll_rst,          // PLL reset
    output wire        pll_bypass,       // PLL bypass
    output wire [2:0]  cdr_gain,         // CDR gain setting
    output wire        cdr_fast_lock,    // CDR fast lock mode
    output wire        cdr_rst,          // CDR reset

    // Debug control outputs
    output wire        dbg_vctrl,        // Debug VCO control voltage
    output wire        dbg_pd,           // Debug phase detector
    output wire        dbg_fifo,         // Debug FIFO status
    output wire        dbg_an,           // Analog debug output

    // Status inputs from PHY blocks (for STATUS register 0x06)
    input  wire        tx_fifo_full,     // TX FIFO full flag
    input  wire        tx_fifo_empty,    // TX FIFO empty flag
    input  wire        tx_overflow,      // TX FIFO overflow (sticky)
    input  wire        tx_underflow,     // TX FIFO underflow (sticky)
    input  wire        rx_fifo_full,     // RX FIFO full flag
    input  wire        rx_fifo_empty,    // RX FIFO empty flag
    input  wire        rx_overflow,      // RX FIFO overflow (sticky)
    input  wire        rx_underflow,     // RX FIFO underflow (sticky)
    input  wire        pll_lock,         // PLL lock indicator
    input  wire        cdr_lock,         // CDR lock indicator
    input  wire        prbs_err          // PRBS error detected (sticky)
);

    // Register interface wires from I2C slave
    wire [7:0] reg_phy_enable;    // 0x00
    wire [7:0] reg_tx_config;     // 0x01
    wire [7:0] reg_rx_config;     // 0x02
    wire [7:0] reg_data_select;   // 0x03
    wire [7:0] reg_pll_config;    // 0x04
    wire [7:0] reg_cdr_config;    // 0x05
    wire [7:0] reg_status;        // 0x06 (read-only)
    wire [7:0] reg_debug_enable;  // 0x07

    // Write notification (optional use)
    wire       reg_write_strobe;
    wire [7:0] reg_write_addr;

    // FIFO error aggregation
    wire fifo_err;
    assign fifo_err = tx_overflow || tx_underflow || rx_overflow || rx_underflow;

    //========================================
    // Status Register Building (0x06 - Read Only)
    //========================================
    assign reg_status = {
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
    // I2C Slave Instantiation
    //========================================
    serdesphy_i2c_slave u_i2c_slave (
        .clk              (clk),
        .rst_n            (rst_n),
        .sda_in           (sda_in),
        .sda_out          (sda_out),
        .sda_oe           (sda_oe),
        .scl              (scl),

        // Register interface
        .reg_phy_enable   (reg_phy_enable),
        .reg_tx_config    (reg_tx_config),
        .reg_rx_config    (reg_rx_config),
        .reg_data_select  (reg_data_select),
        .reg_pll_config   (reg_pll_config),
        .reg_cdr_config   (reg_cdr_config),
        .reg_status       (reg_status),
        .reg_debug_enable (reg_debug_enable),

        // Write notification
        .reg_write_strobe (reg_write_strobe),
        .reg_write_addr   (reg_write_addr)
    );

    //========================================
    // Register Mapping to Control Signals
    //========================================

    // PHY_ENABLE (0x00)
    assign phy_en  = reg_phy_enable[0];
    assign iso_en  = reg_phy_enable[1];

    // TX_CONFIG (0x01)
    assign tx_en       = reg_tx_config[0];
    assign tx_fifo_en  = reg_tx_config[1];
    assign tx_prbs_en  = reg_tx_config[2];
    assign tx_idle     = reg_tx_config[3];

    // RX_CONFIG (0x02)
    assign rx_en           = reg_rx_config[0];
    assign rx_fifo_en      = reg_rx_config[1];
    assign rx_prbs_chk_en  = reg_rx_config[2];
    assign rx_align_rst    = reg_rx_config[3];

    // DATA_SELECT (0x03)
    assign tx_data_sel = reg_data_select[0];
    assign rx_data_sel = reg_data_select[1];

    // PLL_CONFIG (0x04)
    assign vco_trim    = reg_pll_config[3:0];
    assign cp_current  = reg_pll_config[5:4];
    assign pll_rst     = reg_pll_config[6];
    assign pll_bypass  = reg_pll_config[7];

    // CDR_CONFIG (0x05)
    assign cdr_gain      = reg_cdr_config[2:0];
    assign cdr_fast_lock = reg_cdr_config[3];
    assign cdr_rst       = reg_cdr_config[4];

    // DEBUG_ENABLE (0x07)
    assign dbg_vctrl = reg_debug_enable[0];
    assign dbg_pd    = reg_debug_enable[1];
    assign dbg_fifo  = reg_debug_enable[2];

    // Debug analog output (directly from debug_enable)
    assign dbg_an = reg_debug_enable[3];

endmodule
