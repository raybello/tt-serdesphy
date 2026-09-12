// System-level interface for the serdesphy UVM testbench.
//
// Carries every signal the DUT (tt_um_raybello_serdesphy_top) exposes
// once ui_in/uio_in/uo_out/uio_out are unpacked, plus the resolved
// open-drain I2C bus. All signals are plain `logic` (not module
// ports): agents drive/sample them procedurally through a virtual
// interface handle, and system.sv packs/unpacks them onto the DUT's
// Tiny Tapeout bus.

interface system_if;

  // ------------------------------------------------------------------
  // Reference clock / reset (driven by clk_reset_driver)
  // ------------------------------------------------------------------
  logic clk_ref_24m;
  logic dut_rst_n;

  // ------------------------------------------------------------------
  // TX stimulus / static configuration
  // ------------------------------------------------------------------
  logic [3:0] tx_data;
  logic       tx_valid;
  logic       test_mode;
  logic       lpbk_en;

  // ------------------------------------------------------------------
  // Observed DUT outputs
  // ------------------------------------------------------------------
  logic [3:0] rx_data;
  logic       rx_valid;
  logic       pll_lock;
  logic       cdr_lock;
  logic       prbs_err;
  logic       txp;
  logic       txn;
  logic       rxp;
  logic       rxn;

  // ------------------------------------------------------------------
  // I2C bus (open-drain, wired-AND). scl is master-only (no clock
  // stretching modeled). sda is resolved from both the i2c_driver's
  // and the DUT's open-drain contributions.
  // ------------------------------------------------------------------
  logic scl;
  logic mst_sda_drive_low;  // set by i2c_driver
  logic slv_sda_drive_low;  // set by system.sv from the DUT's sda_oe
  wire  sda = (mst_sda_drive_low || slv_sda_drive_low) ? 1'b0 : 1'b1;

endinterface : system_if
