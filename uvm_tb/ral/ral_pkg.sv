// RAL package: the register model on its own, independent of any
// particular bus/agent. serdesphy_pkg imports this and supplies the
// bus-specific piece (csr2i2c_adapter, see ral/csr2i2c_adapter.sv)
// that connects it to i2c_agent.

package ral_pkg;

  import uvm_pkg::*;
`include "uvm_macros.svh"

  import system_pkg::*;

  `include "ral.sv"
  `include "csr_reg_model.sv"

endpackage : ral_pkg
