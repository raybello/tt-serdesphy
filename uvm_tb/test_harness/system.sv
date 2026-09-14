// Instantiates the DUT (tt_um_raybello_serdesphy_top) and packs/unpacks
// its Tiny Tapeout ui_in/uio_in/uo_out/uio_out buses onto system_if.
//
// This is the module tb_top.sv instantiates; it owns no stimulus of
// its own (clocks/reset come from clk_reset_agent, CSR access comes
// from i2c_agent) - it is pure wiring.

`timescale 1ns / 1ps

module system (
    system_if vif
);

  import system_pkg::*;

  logic       ena = 1'b1;
  logic       clk = 1'b0;    // unused by the design itself
  logic       rst_n = 1'b1;  // unused by the design itself

  logic [7:0] ui_in;
  logic [7:0] uio_in;
  wire  [7:0] uo_out;
  wire  [7:0] uio_out;
  wire  [7:0] uio_oe;

  // test_mode/lpbk_en/tx_data/tx_valid are driven by phy_io_agent
  // (uvm_tb/agents/phy_io_agent); rxp/rxn are unused in loopback mode
  // (lpbk_en routes the TX driver's own output back into the RX front
  // end inside serdesphy_pma.v) and tied off here since no standalone
  // serial RX stimulus driver exists.
  assign vif.rxp = 1'b0;
  assign vif.rxn = 1'b0;

  // ------------------------------------------------------------------
  // Pack/unpack the Tiny Tapeout ui_in / uio_in / uo_out buses
  // ------------------------------------------------------------------
  assign ui_in[0]   = vif.clk_ref_24m;
  assign ui_in[1]   = vif.dut_rst_n;
  assign ui_in[5:2] = vif.tx_data;
  assign ui_in[6]   = vif.tx_valid;
  assign ui_in[7]   = vif.test_mode;

  assign uio_in[0] = vif.sda;
  assign uio_in[1] = vif.scl;
  assign uio_in[2] = 1'b0;  // txp (output)
  assign uio_in[3] = 1'b0;  // txn (output)
  assign uio_in[4] = vif.rxp;
  assign uio_in[5] = vif.rxn;
  assign uio_in[6] = vif.lpbk_en;
  assign uio_in[7] = 1'b0;  // dbg_ana (output)

  // The DUT's SDA line is open-drain: sda_out is always driven 0, so
  // whether it pulls the shared bus low is entirely governed by
  // sda_oe (uio_oe[0]).
  assign vif.slv_sda_drive_low = uio_oe[0];

  assign vif.rx_data  = uo_out[3:0];
  assign vif.pll_lock = uo_out[4];
  assign vif.cdr_lock = uo_out[5];
  assign vif.prbs_err = uo_out[6];
  assign vif.rx_valid = uo_out[7];
  assign vif.txp      = uio_out[2];
  assign vif.txn      = uio_out[3];

  // ------------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------------
  tt_um_raybello_serdesphy_top dut (
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

endmodule : system
