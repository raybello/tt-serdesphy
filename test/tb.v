`default_nettype none
`timescale 1ns / 1ps

/* SerDes PHY Testbench
 * This testbench connects all signals properly and provides clock generation
 * for comprehensive testing via cocotb test.py.
 */
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Tiny Tapeout interface signals
  reg clk;                    // System clock (from cocotb)
  reg rst_n;                  // System reset (from cocotb)  
  reg ena;                    // Enable (always 1)
  reg [7:0] ui_in;            // Dedicated inputs
  reg [7:0] uio_in;           // IO inputs
  wire [7:0] uo_out;          // Dedicated outputs
  wire [7:0] uio_out;         // IO outputs
  wire [7:0] uio_oe;          // IO output enables

  // Testbench control signals
  reg clk_ref_24m;            // 24MHz reference clock (ui_in[0])
  reg test_mode;              // Test mode enable (ui_in[7])
  reg lpbk_en;                // Loopback enable (uio_in[6])
  reg scl;                    // I2C clock (uio_in[1])
  reg [3:0] tx_data;          // TX data [3:0] (ui_in[5:2])
  reg tx_valid;               // TX valid (ui_in[6])
  reg rxp;                    // RX+ differential (uio_in[4])
  reg rxn;                    // RX- differential (uio_in[5])

  // Output monitoring signals (from uo_out)
  wire pll_lock;              // PLL lock indicator (uo_out[4])
  wire cdr_lock;              // CDR lock indicator (uo_out[5])
  wire prbs_err;              // PRBS error flag (uo_out[6])
  wire dbg_ana;               // Debug analog output (uo_out[7])
  wire [3:0] rx_data;         // RX data [3:0] (uo_out[3:0])
  wire rx_valid;              // RX valid (uo_out[7])

  // SDA bidirectional handling (open-drain)
  wire sda_internal;
  reg sda_out;                // Testbench SDA output
  reg sda_oe;                 // Testbench SDA output enable

  // 24MHz clock generation
  initial begin
    clk_ref_24m = 0;
    forever #21 clk_ref_24m = ~clk_ref_24m;  // 24MHz = 42ns period
  end

  // SDA tri-state handling
  assign sda_internal = (sda_oe) ? sda_out : 1'b1;  // Default high when not driven
  
  // Map Tiny Tapeout signals to testbench controls
  assign ui_in[0] = clk_ref_24m;    // 24MHz reference clock
  assign ui_in[1] = rst_n;          // Reset
  assign ui_in[2] = tx_data[0];     // TX data bit 0
  assign ui_in[3] = tx_data[1];     // TX data bit 1
  assign ui_in[4] = tx_data[2];     // TX data bit 2
  assign ui_in[5] = tx_data[3];     // TX data bit 3
  assign ui_in[6] = tx_valid;       // TX valid
  assign ui_in[7] = test_mode;      // Test mode enable

  // Map UIO inputs
  assign uio_in[1] = scl;           // I2C clock
  assign uio_in[4] = rxp;           // RX+ differential
  assign uio_in[5] = rxn;           // RX- differential
  assign uio_in[6] = lpbk_en;       // Loopback enable

  // Handle SDA bidirectional (uio_out[0]/uio_in[0])
  assign uio_in[0] = sda_internal;
  
  // Unused UIO inputs
  assign uio_in[2] = 1'b0;          // TXP (output)
  assign uio_in[3] = 1'b0;          // TXN (output)
  assign uio_in[7] = 1'b0;          // DBG_ANA (output)

  // Extract output signals
  assign pll_lock = uo_out[4];      // PLL lock indicator
  assign cdr_lock = uo_out[5];      // CDR lock indicator  
  assign prbs_err = uo_out[6];      // PRBS error flag
  assign dbg_ana = uo_out[7];       // Debug analog output
  assign rx_data = uo_out[3:0];     // RX data [3:0]
  assign rx_valid = uo_out[7];      // RX valid (bit 7, also dbg_ana)

  // DUT instantiation
  tt_um_raybello_serdesphy_top user_project (
      .ui_in  (ui_in),              // Dedicated inputs
      .uo_out (uo_out),             // Dedicated outputs
      .uio_in (uio_in),             // IOs: Input path
      .uio_out(uio_out),            // IOs: Output path
      .uio_oe (uio_oe),             // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),                // enable - goes high when design is selected
      .clk    (clk),                // clock
      .rst_n  (rst_n)               // not reset
  );

endmodule
