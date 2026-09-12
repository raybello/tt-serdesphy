// Brings the DUT's CSRs up into an operational configuration via the
// RAL frontdoor (see docs/info.md section 8.1 init sequence, steps
// 3-4/8): enable the PHY and release the PLL/CDR resets. Requires
// clk_ref_24m to already be running and dut_rst_n deasserted (run
// cold_reset_vseq first). The reg_model convenience tasks check their
// own status and raise `uvm_error` on failure, so no need to check
// here.

class csr_init_vseq extends base_vseq;

  `uvm_object_utils(csr_init_vseq)

  function new(string name = "csr_init_vseq");
    super.new(name);
  endfunction

  task body();
    regmodel.enable_phy(1'b1, this);
    regmodel.set_pll_reset(1'b0, this);
    regmodel.set_cdr_reset(1'b0, this);
  endtask : body

endclass : csr_init_vseq
