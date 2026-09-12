// Plain (non-UVM) package holding types shared by the test harness,
// the checkers and the RAL model: the CSR address map and the I2C
// device address. Kept separate from serdesphy_pkg (the UVM
// environment) so that low-level, non-verification code does not need
// to pull in the whole UVM class library.

`include "defines.sv"

package system_pkg;

  // CSR register addresses (see src/digital/csr/serdesphy_registerInterface.v)
  typedef enum bit [2:0] {
    REG_PHY_ENABLE   = 3'h0,
    REG_TX_CONFIG    = 3'h1,
    REG_RX_CONFIG    = 3'h2,
    REG_DATA_SELECT  = 3'h3,
    REG_PLL_CONFIG   = 3'h4,
    REG_CDR_CONFIG   = 3'h5,
    REG_STATUS       = 3'h6,
    REG_DEBUG_ENABLE = 3'h7
  } csr_addr_e;

  parameter bit [6:0] I2C_DEV_ADDR = `SERDESPHY_I2C_DEV_ADDR;

endpackage : system_pkg
