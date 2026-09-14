// Brings the DUT's CSRs up into an operational configuration via the
// RAL frontdoor (see docs/info.md section 8.1 init sequence, steps
// 3-4/8): enable the PHY, release analog isolation, and release the
// PLL/CDR resets. Requires clk_ref_24m to already be running and
// dut_rst_n deasserted (run cold_reset_vseq first). The reg_model
// convenience tasks check their own status and raise `uvm_error` on
// failure, so no need to check here.
//
// set_isolation(0) matters, not just enable_phy(1): docs/info.md 8.1
// step 3 writes 0x01 to PHY_ENABLE in one shot, which sets PHY_EN=1 AND
// clears ISO_EN (bit 1, default 1 = isolated) together. enable_phy()
// only ever touches bit 0 (a read-modify-write, since our I2C bus can't
// write less than a whole byte - see csr_reg_model.sv), so without this
// separate call ISO_EN stays at its power-on default of 1 and
// serdesphy_pma.v's analog_en never asserts: the analog PLL/CDR are held
// isolated forever, regardless of PHY_EN or PLL_RST/CDR_RST. This was
// latent in every test built on this vseq until a test that actually
// depends on the analog PLL/CDR locking (tx_rx_loopback_test) exercised
// it - see docs/implementation/01-spec-vs-implementation.md.
class csr_init_vseq extends base_vseq;

  `uvm_object_utils(csr_init_vseq)

  function new(string name = "csr_init_vseq");
    super.new(name);
  endfunction

  task body();
    regmodel.enable_phy(1'b1, this);
    regmodel.set_isolation(1'b0, this);
    regmodel.set_pll_reset(1'b0, this);
    regmodel.set_cdr_reset(1'b0, this);
  endtask : body

endclass : csr_init_vseq
