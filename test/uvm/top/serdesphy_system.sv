`ifndef _SERDESPHY_TB_TOP_SV_
`define _SERDESPHY_TB_TOP_SV_

module serdesphy_system;
   import uvm_pkg::*;
   `include "uvm_macros.svh"

   sys_if     sys_vi();

   serdesphy_if serdesphy_vi();

   initial begin
      uvm_config_db #(virtual sys_if)::set(null, "*", "sys_vi", sys_vi);
      uvm_config_db #(virtual serdesphy_if)::set(null, "*", "dut_vif", serdesphy_vi);
   end

   assign   serdesphy_vi.clk     = sys_vi.clk;
   assign   serdesphy_vi.rst_n   = sys_vi.rst_n;

   // Device Under Test
   memory dut (
      .clk  (sys_vi.clk),
      .reset(sys_vi.rst_n),
      .addr (serdesphy_vi.addr),
      .wr_en(serdesphy_vi.wr_en),
      .rd_en(serdesphy_vi.rd_en),
      .wdata(serdesphy_vi.wdata),
      .rdata(serdesphy_vi.rdata)
   );

   initial begin
      $dumpfile("dumpfile.vcd");
      $dumpvars;
   end

   test_initiator   u_test_initiator();

endmodule
`endif
