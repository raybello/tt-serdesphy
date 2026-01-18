module test_initiator;
   import uvm_pkg::*;
   `include "uvm_macros.svh"

   import common_pkg::*;
   import serdesphy_test_pkg::*;

   initial begin
      run_test();
   end

   final begin
      uvm_report_server   svr;

      svr = uvm_report_server::get_server();

      if (svr.get_severity_count(UVM_FATAL) || svr.get_severity_count(UVM_ERROR))
         `DISPLAY_FAIL
      else
         `DISPLAY_PASS
   end
endmodule
