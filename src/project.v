/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_raybello_serdesphy_top (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Internal wires for SDA bidirectional handling
  wire sda_out_internal;
  wire sda_oe_internal;

  // SDA open-drain implementation:
  // - sda_out is always 0 (pull low when enabled)
  // - sda_oe controls when to drive low (1 = drive low, 0 = release/input)
  assign uio_out[0] = sda_out_internal;  // Always 0 from slave
  assign uio_oe[0]  = sda_oe_internal;   // Enable output when slave drives low
  
  // Configure bidirectional pin directions
  // Outputs: TXP, TXN, DBG_ANA
  assign uio_oe[2] = 1'b1;   // TXP is output
  assign uio_oe[3] = 1'b1;   // TXN is output  
  assign uio_oe[7] = 1'b1;   // DBG_ANA is output
  
  // Inputs: SCL, RXP, RXN, LPBK_EN
  assign uio_oe[1] = 1'b0;   // SCL is input
  assign uio_oe[4] = 1'b0;   // RXP is input
  assign uio_oe[5] = 1'b0;   // RXN is input
  assign uio_oe[6] = 1'b0;   // LPBK_EN is input
  
  // Set unused bidirectional outputs to 0
  assign uio_out[1] = 1'b0;  // SCL (input)
  assign uio_out[4] = 1'b0;  // RXP (input)
  assign uio_out[5] = 1'b0;  // RXN (input)
  assign uio_out[6] = 1'b0;  // LPBK_EN (input)

  serdesphy_top u_top(
    // Reset & Clock
    .clk_ref_24m(ui_in[0]),     // 24 MHz reference clock
    .rst_n      (ui_in[1]),     // Active-low reset
    .pll_lock   (uo_out[4]),    // PLL lock indicator
    
    // CSR Interface - I2C with separate signals for open-drain handling
    .sda_in     (uio_in[0]),        // SDA input (from master)
    .sda_out    (sda_out_internal), // SDA output (always 0, used with oe)
    .sda_oe     (sda_oe_internal),  // SDA output enable (1 = drive low)
    .scl        (uio_in[1]),        // I2C clock (input)
    
    // Transmit
    .tx_data    (ui_in[5:2]),   // TX data bits [3:0]
    .tx_valid   (ui_in[6]),     // TX data valid strobe
    .txp        (uio_out[2]),   // TX differential (+)
    .txn        (uio_out[3]),   // TX differential (-)
    
    // Receive
    .rx_data    (uo_out[3:0]),  // RX data bits [3:0]
    .rx_valid   (uo_out[7]),    // RX data valid strobe
    .cdr_lock   (uo_out[5]),    // CDR lock indicator
    .prbs_err   (uo_out[6]),    // PRBS error flag
    .rxp        (uio_in[4]),    // RX differential (+)
    .rxn        (uio_in[5]),    // RX differential (-)
    
    // Configuration
    .test_mode  (ui_in[7]),     // Test mode enable
    .lpbk_en    (uio_in[6]),    // Analog loopback enable
    .dbg_ana    (uio_out[7]),   // Analog debug buffer
    
    // Power Monitoring
    .dvdd_ok    (ena),          // 1.8V digital supply OK
    .avdd_ok    (ena)           // 3.3V analog supply OK

  );


  // List all unused inputs to prevent warnings
  wire _unused = &{clk, rst_n, 1'b0};

endmodule
