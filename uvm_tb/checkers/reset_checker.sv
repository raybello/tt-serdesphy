// Passive checker bound onto system_if: verifies dut_rst_n is held
// asserted for at least MIN_RESET_CYCLES clk_ref_24m cycles before
// being deasserted. Too-short a reset pulse would leave the design's
// synchronous reset chain (serdesphy_reset_synchronizer) and the I2C
// debounce logic in an undefined state.

`include "defines.sv"

module reset_checker #(
    parameter int MIN_RESET_CYCLES = `SERDESPHY_MIN_RESET_CYCLES
) (
    input logic clk,
    input logic rst_n
);

  import uvm_pkg::*;
`include "uvm_macros.svh"

  int unsigned assert_cycles = 0;
  logic        rst_n_q       = 1'b1;

  always @(posedge clk) begin
    if (!rst_n)
      assert_cycles <= assert_cycles + 1'b1;

    // Rising edge of rst_n: reset just deasserted.
    if (rst_n && !rst_n_q) begin
      if (assert_cycles < MIN_RESET_CYCLES)
        `uvm_error("RESET_CHECK",
                   $sformatf("dut_rst_n deasserted after only %0d clk_ref_24m cycle(s), expected >= %0d",
                              assert_cycles, MIN_RESET_CYCLES))
      assert_cycles <= 0;
    end

    rst_n_q <= rst_n;
  end

endmodule : reset_checker
